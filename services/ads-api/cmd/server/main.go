package main

import (
	"ads-api/internal/handler"
	"ads-api/internal/service"
	"ads-api/internal/store"
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
	dsn := os.Getenv("DB_DSN")
	if dsn == "" {
		panic("DB_DSN is not set")
	}
	jwtSecret := os.Getenv("SECRET_KEY")
	if jwtSecret == "" {
		panic("SECRET_KEY is not set")
	}

	db, err := store.NewMySQL(dsn)
	if err != nil {
		panic(err)
	}
	defer db.Close()

	tarantoolDSN := os.Getenv("TARANTOOL_DSN")
	if tarantoolDSN == "" {
		tarantoolDSN = "127.0.0.1:33013"
	}

	tarantoolStore, err := store.NewTarantoolStore(tarantoolDSN)
	if err != nil {
		fmt.Printf("Warning: Failed to connect to Tarantool: %v\n", err)
		fmt.Println("Continuing without caching...")
	} else {
		defer tarantoolStore.Close()
		fmt.Println("Tarantool cache store initialized successfully")
	}

	rabbitmqURL := os.Getenv("RABBITMQ_URL")
	if rabbitmqURL == "" {
		rabbitmqURL = "amqp://guest:guest@rabbitmq:5672/"
	}
	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		redisURL = "redis://redis:6379/0"
	}

	rabbitmqService, err := service.NewRabbitMQService(rabbitmqURL)
	if err != nil {
		fmt.Printf("Warning: Failed to connect to RabbitMQ: %v\n", err)
		fmt.Println("Continuing without message queuing...")
	} else {
		defer rabbitmqService.Close()
		fmt.Println("RabbitMQ service initialized successfully")
	}

	campaignStore := store.NewCampaignStore(db)
	campaignService := service.NewCampaignService(campaignStore)
	campaignHandler := handler.NewCampaignHandler(campaignService)

	adStore := store.NewAdStore(db)
	adService := service.NewAdService(adStore, rabbitmqService)
	adHandler := handler.NewAdHandler(adService)

	mediaDirectory := os.Getenv("MEDIA_STORAGE_PATH")
	if mediaDirectory == "" {
		mediaDirectory = "/data/media"
	}
	creativeStore := store.NewCreativeStore(db)
	creativeService := service.NewCreativeServiceWithStorage(creativeStore, service.NewMediaStorage(mediaDirectory))
	creativeHandler := handler.NewCreativeHandler(creativeService)

	inventoryStore := store.NewInventoryStore(db)
	inventoryService := service.NewInventoryService(inventoryStore)
	inventoryHandler := handler.NewInventoryHandler(inventoryService)

	deliveryStore := store.NewDeliveryStore(db)
	deliveryService := service.NewDeliveryService(deliveryStore)
	deliveryHandler := handler.NewDeliveryHandler(deliveryService)
	authorizationStore, err := store.NewAuthorizationStore(db, redisURL)
	if err != nil {
		panic(err)
	}
	defer authorizationStore.Close()
	appCtx, cancelApp := context.WithCancel(context.Background())
	defer cancelApp()
	go service.NewDeliveryDispatcher(deliveryStore, rabbitmqService).Run(appCtx)
	if rabbitmqService != nil {
		go rabbitmqService.ConsumeUserBlocked(appCtx, authorizationStore.ApplyUserBlocked)
	}

	r := gin.New()
	r.MaxMultipartMemory = 8 << 20
	r.Use(handler.RequestID(),
		handler.Logger(),
		handler.TimeoutWithMultipart(3*time.Second, 2*time.Minute),
		gin.Recovery(),
	)

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "OK"})
	})

	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "ads-api running"})
	})

	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	private := r.Group("")
	private.Use(handler.Authenticate(jwtSecret, authorizationStore))

	private.POST("/campaigns", campaignHandler.Create)
	private.GET("/campaigns", campaignHandler.List)
	private.GET("/campaigns/:id", campaignHandler.Get)
	private.PUT("/campaigns/:id", campaignHandler.Update)
	private.DELETE("/campaigns/:id", campaignHandler.Delete)

	private.POST("/ads", adHandler.Create)
	private.GET("/ads", adHandler.List)
	private.GET("/ads/:id", adHandler.Get)
	private.PUT("/ads/:id", adHandler.Update)
	private.DELETE("/ads/:id", adHandler.Delete)

	private.POST("/creatives", creativeHandler.Create)
	private.POST("/creatives/upload", creativeHandler.Upload)
	private.GET("/creatives", creativeHandler.List)
	private.GET("/creatives/:id", creativeHandler.Get)
	private.PUT("/creatives/:id", creativeHandler.Update)
	private.PUT("/creatives/:id/upload", creativeHandler.UpdateUpload)
	private.DELETE("/creatives/:id", creativeHandler.Delete)
	private.POST("/creatives/:id/submit", creativeHandler.SubmitForModeration)
	private.GET(
		"/moderation/creatives",
		handler.RequirePermission("moderation.review"),
		creativeHandler.ListModeration,
	)
	private.POST(
		"/moderation/creatives/:id/review",
		handler.RequirePermission("moderation.review"),
		creativeHandler.ReviewModeration,
	)
	r.GET("/media/:filename", func(c *gin.Context) {
		filename := c.Param("filename")
		if filename == "" || filepath.Base(filename) != filename {
			c.Status(http.StatusNotFound)
			return
		}
		fullPath := filepath.Join(mediaDirectory, filename)
		info, err := os.Stat(fullPath)
		if err != nil || info.IsDir() {
			c.Status(http.StatusNotFound)
			return
		}
		c.Header("Cache-Control", "public, max-age=31536000, immutable")
		c.File(fullPath)
	})

	private.POST("/sites", inventoryHandler.CreateSite)
	private.GET("/sites", inventoryHandler.ListSites)
	private.GET("/sites/:id", inventoryHandler.GetSite)
	private.PUT("/sites/:id", inventoryHandler.UpdateSite)
	private.DELETE("/sites/:id", inventoryHandler.DeleteSite)

	private.POST("/formats", handler.RequirePermission("users.roles.manage"), inventoryHandler.CreateFormat)
	private.GET("/formats", inventoryHandler.ListFormats)
	private.GET("/formats/:id", inventoryHandler.GetFormat)
	private.PUT("/formats/:id", handler.RequirePermission("users.roles.manage"), inventoryHandler.UpdateFormat)
	private.DELETE("/formats/:id", handler.RequirePermission("users.roles.manage"), inventoryHandler.DeleteFormat)

	private.POST("/placements", inventoryHandler.CreatePlacement)
	private.GET("/placements", inventoryHandler.ListPlacements)
	private.GET("/placements/:id", inventoryHandler.GetPlacement)
	private.PUT("/placements/:id", inventoryHandler.UpdatePlacement)
	private.DELETE("/placements/:id", inventoryHandler.DeletePlacement)

	r.POST("/delivery/select", deliveryHandler.Select)
	r.POST("/delivery/:id/impression", deliveryHandler.Impression)
	r.POST("/delivery/:id/click", deliveryHandler.Click)
	r.GET("/delivery/:id/click", deliveryHandler.ClickAndRedirect)
	r.POST("/delivery/:id/conversion", deliveryHandler.Conversion)
	r.POST("/attribution/conversion", deliveryHandler.AttributedConversion)

	srv := &http.Server{
		Addr:    ":8080",
		Handler: r,
	}
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Printf("listen: %s\n", err)
		}
	}()
	fmt.Println("ads-api: listening on :8080")

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	<-quit

	fmt.Println("ads-api: shutting down...")
	cancelApp()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		fmt.Printf("Server forced to shutdown: %v\n", err)
	}
	fmt.Println("ads-api: stopped")
}
