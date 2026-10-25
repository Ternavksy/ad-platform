package handler

import (
	"ads-api/internal/model"
	"ads-api/internal/service"
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

type DeliveryHandler struct {
	service *service.DeliveryService
}

func NewDeliveryHandler(s *service.DeliveryService) *DeliveryHandler {
	return &DeliveryHandler{service: s}
}

func (h *DeliveryHandler) Select(c *gin.Context) {
	var req model.DeliveryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	item, err := h.service.Select(c.Request.Context(), req)
	if errors.Is(err, service.ErrNoDelivery) {
		c.Status(http.StatusNoContent)
		return
	}
	if err != nil {
		HandleError(c, err)
		return
	}
	item.ImpressionURL = absoluteTrackingURL(c, item.ImpressionURL)
	item.ClickURL = absoluteTrackingURL(c, item.ClickURL)
	item.ConversionURL = absoluteTrackingURL(c, item.ConversionURL)
	c.JSON(http.StatusOK, item)
}

func absoluteTrackingURL(c *gin.Context, path string) string {
	scheme := strings.TrimSpace(strings.Split(c.GetHeader("X-Forwarded-Proto"), ",")[0])
	if scheme != "https" && scheme != "http" {
		scheme = "http"
	}
	return scheme + "://" + c.Request.Host + path
}

func (h *DeliveryHandler) Impression(c *gin.Context) {
	result, err := h.service.TrackImpression(c.Request.Context(), c.Param("id"))
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, result)
}

func (h *DeliveryHandler) Click(c *gin.Context) {
	item, result, err := h.service.TrackClick(c.Request.Context(), c.Param("id"))
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"delivery_id":     item.ID,
		"event_id":        result.EventID,
		"event_type":      result.EventType,
		"recorded":        result.Recorded,
		"occurred_at":     result.OccurredAt,
		"clicked":         true,
		"destination_url": item.DestinationURL,
	})
}

func (h *DeliveryHandler) ClickAndRedirect(c *gin.Context) {
	item, _, err := h.service.TrackClick(c.Request.Context(), c.Param("id"))
	if err != nil {
		HandleError(c, err)
		return
	}
	c.Redirect(http.StatusFound, item.DestinationURL)
}

func (h *DeliveryHandler) Conversion(c *gin.Context) {
	var req model.ConversionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	result, err := h.service.TrackConversion(c.Request.Context(), c.Param("id"), req)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, result)
}
