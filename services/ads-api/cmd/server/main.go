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
	appCtx, cancelApp := context.WithCancel(context.Background())
	defer cancelApp()
	go service.NewDeliveryDispatcher(deliveryStore, rabbitmqService).Run(appCtx)

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

	r.POST("/campaigns", campaignHandler.Create)
	r.GET("/campaigns", campaignHandler.List)
	r.GET("/campaigns/:id", campaignHandler.Get)
	r.PUT("/campaigns/:id", campaignHandler.Update)
	r.DELETE("/campaigns/:id", campaignHandler.Delete)

	r.POST("/ads", adHandler.Create)
	r.GET("/ads", adHandler.List)
	r.GET("/ads/:id", adHandler.Get)
	r.PUT("/ads/:id", adHandler.Update)
	r.DELETE("/ads/:id", adHandler.Delete)

	r.POST("/creatives", creativeHandler.Create)
	r.POST("/creatives/upload", creativeHandler.Upload)
	r.GET("/creatives", creativeHandler.List)
	r.GET("/creatives/:id", creativeHandler.Get)
	r.PUT("/creatives/:id", creativeHandler.Update)
	r.PUT("/creatives/:id/upload", creativeHandler.UpdateUpload)
	r.DELETE("/creatives/:id", creativeHandler.Delete)
	r.POST("/creatives/:id/submit", handler.Authenticate(jwtSecret), creativeHandler.SubmitForModeration)
	r.GET(
		"/moderation/creatives",
		handler.Authenticate(jwtSecret),
		handler.RequireRole("admin"),
		creativeHandler.ListModeration,
	)
	r.POST(
		"/moderation/creatives/:id/review",
		handler.Authenticate(jwtSecret),
		handler.RequireRole("admin"),
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

	r.POST("/sites", inventoryHandler.CreateSite)
	r.GET("/sites", inventoryHandler.ListSites)
	r.GET("/sites/:id", inventoryHandler.GetSite)
	r.PUT("/sites/:id", inventoryHandler.UpdateSite)
	r.DELETE("/sites/:id", inventoryHandler.DeleteSite)

	r.POST("/formats", inventoryHandler.CreateFormat)
	r.GET("/formats", inventoryHandler.ListFormats)
	r.GET("/formats/:id", inventoryHandler.GetFormat)
	r.PUT("/formats/:id", inventoryHandler.UpdateFormat)
	r.DELETE("/formats/:id", inventoryHandler.DeleteFormat)

	r.POST("/placements", inventoryHandler.CreatePlacement)
	r.GET("/placements", inventoryHandler.ListPlacements)
	r.GET("/placements/:id", inventoryHandler.GetPlacement)
	r.PUT("/placements/:id", inventoryHandler.UpdatePlacement)
	r.DELETE("/placements/:id", inventoryHandler.DeletePlacement)

	r.POST("/delivery/select", deliveryHandler.Select)
	r.POST("/delivery/:id/click", deliveryHandler.Click)
	r.GET("/delivery/:id/click", deliveryHandler.ClickAndRedirect)

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
