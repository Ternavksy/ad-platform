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
	"time"

	"github.com/gin-gonic/gin"
)

func main() {
	dsn := os.Getenv("DB_DSN")
	if dsn == "" {
		panic("DB_DSN is not set")
	}

	db, err := store.NewMySQL(dsn)
	if err != nil {
		panic(err)
	}
	defer db.Close()

	campaignStore := store.NewCampaignStore(db)

	campaignService := service.NewCampaignService(campaignStore)

	campaignHandler := handler.NewCampaignHandler(campaignService)

	r := gin.New()
	r.Use(handler.RequestID(),
		handler.Logger(),
		handler.Timeout(3*time.Second),
		gin.Recovery(),
	)

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "OK"})
	})

	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "ads-api running"})
	})

	r.POST("/campaigns", campaignHandler.Create)
	r.GET("/campaigns/:id", campaignHandler.Get)

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
	signal.Notify(quit, os.Interrupt)
	<-quit

	fmt.Println("ads-api: shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		fmt.Printf("Server forced to shutdown: %v\n", err)
	}
	fmt.Println("ads-api: stopped")
}
