package handler

import (
	"context"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func Timeout(d time.Duration) gin.HandlerFunc {
	return TimeoutWithMultipart(d, d)
}

func TimeoutWithMultipart(defaultDuration, multipartDuration time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		duration := defaultDuration
		if strings.HasPrefix(strings.ToLower(c.GetHeader("Content-Type")), "multipart/form-data") {
			duration = multipartDuration
		}
		ctx, cancel := context.WithTimeout(c.Request.Context(), duration)
		defer cancel()
		c.Request = c.Request.WithContext(ctx)
		c.Next()
	}
}
