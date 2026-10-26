package handler

import (
	"ads-api/internal/model"
	"ads-api/internal/service"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type AdHandler struct {
	service *service.AdService
}

func NewAdHandler(s *service.AdService) *AdHandler {
	return &AdHandler{service: s}
}

func (h *AdHandler) Create(c *gin.Context) {
	principal, ok := CurrentPrincipal(c)
	if !ok {
		HandleError(c, service.ErrForbidden)
		return
	}
	var req model.Ad
	if err := c.ShouldBindJSON(&req); err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	owned, err := h.service.CampaignOwnedByUser(c.Request.Context(), req.CampaignID, principal.UserID)
	if err != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	if err := h.service.Create(c.Request.Context(), &req); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusCreated, req)
}

func (h *AdHandler) List(c *gin.Context) {
	campaignID, err := strconv.ParseInt(c.Query("campaign_id"), 10, 64)
	if err != nil || campaignID <= 0 {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.CampaignOwnedByUser(c.Request.Context(), campaignID, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	items, err := h.service.ListByCampaign(c.Request.Context(), campaignID)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, items)
}

func (h *AdHandler) Get(c *gin.Context) {
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.OwnedByUser(c.Request.Context(), id, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}

	ad, err := h.service.GetByID(c.Request.Context(), id)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, ad)
}

func (h *AdHandler) Update(c *gin.Context) {
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.OwnedByUser(c.Request.Context(), id, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	var req model.Ad
	if err := c.ShouldBindJSON(&req); err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	req.ID = id
	if err := h.service.Update(c.Request.Context(), &req); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, req)
}

func (h *AdHandler) Delete(c *gin.Context) {
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.OwnedByUser(c.Request.Context(), id, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	if err := h.service.Delete(c.Request.Context(), id); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}
