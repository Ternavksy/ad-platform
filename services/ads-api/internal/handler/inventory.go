package handler

import (
	"ads-api/internal/model"
	"ads-api/internal/service"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type InventoryHandler struct {
	service *service.InventoryService
}

func NewInventoryHandler(s *service.InventoryService) *InventoryHandler {
	return &InventoryHandler{service: s}
}

func pathID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		HandleError(c, service.ErrNotFound)
		return 0, false
	}
	return id, true
}

func (h *InventoryHandler) CreateSite(c *gin.Context) {
	principal, ok := CurrentPrincipal(c)
	if !ok {
		HandleError(c, service.ErrForbidden)
		return
	}
	var item model.Site
	if c.ShouldBindJSON(&item) != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	item.UserID = principal.UserID
	if err := h.service.CreateSite(c.Request.Context(), &item); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusCreated, item)
}

func (h *InventoryHandler) GetSite(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	item, err := h.service.GetSite(c.Request.Context(), id)
	if err != nil {
		HandleError(c, err)
		return
	}
	principal, ok := CurrentPrincipal(c)
	if !ok || item.UserID != principal.UserID {
		HandleError(c, service.ErrForbidden)
		return
	}
	c.JSON(http.StatusOK, item)
}

func (h *InventoryHandler) ListSites(c *gin.Context) {
	principal, ok := CurrentPrincipal(c)
	if !ok {
		HandleError(c, service.ErrForbidden)
		return
	}
	items, err := h.service.ListSites(c.Request.Context(), principal.UserID)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, items)
}

func (h *InventoryHandler) UpdateSite(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	principal, authenticated := CurrentPrincipal(c)
	owned, ownershipErr := h.service.SiteOwnedByUser(c.Request.Context(), id, principal.UserID)
	if !authenticated || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	var item model.Site
	if c.ShouldBindJSON(&item) != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	item.ID = id
	if err := h.service.UpdateSite(c.Request.Context(), &item); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, item)
}

func (h *InventoryHandler) DeleteSite(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	principal, authenticated := CurrentPrincipal(c)
	owned, ownershipErr := h.service.SiteOwnedByUser(c.Request.Context(), id, principal.UserID)
	if !authenticated || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	if err := h.service.DeleteSite(c.Request.Context(), id); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}

func (h *InventoryHandler) CreateFormat(c *gin.Context) {
	var item model.AdFormat
	if c.ShouldBindJSON(&item) != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	if err := h.service.CreateFormat(c.Request.Context(), &item); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusCreated, item)
}

func (h *InventoryHandler) GetFormat(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	item, err := h.service.GetFormat(c.Request.Context(), id)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, item)
}

func (h *InventoryHandler) ListFormats(c *gin.Context) {
	items, err := h.service.ListFormats(c.Request.Context())
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, items)
}

func (h *InventoryHandler) UpdateFormat(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	var item model.AdFormat
	if c.ShouldBindJSON(&item) != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	item.ID = id
	if err := h.service.UpdateFormat(c.Request.Context(), &item); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, item)
}

func (h *InventoryHandler) DeleteFormat(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	if err := h.service.DeleteFormat(c.Request.Context(), id); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}

func (h *InventoryHandler) CreatePlacement(c *gin.Context) {
	var item model.Placement
	if c.ShouldBindJSON(&item) != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.SiteOwnedByUser(c.Request.Context(), item.SiteID, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	if err := h.service.CreatePlacement(c.Request.Context(), &item); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusCreated, item)
}

func (h *InventoryHandler) GetPlacement(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	item, err := h.service.GetPlacement(c.Request.Context(), id)
	if err != nil {
		HandleError(c, err)
		return
	}
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.SiteOwnedByUser(c.Request.Context(), item.SiteID, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	c.JSON(http.StatusOK, item)
}

func (h *InventoryHandler) ListPlacements(c *gin.Context) {
	siteID, err := strconv.ParseInt(c.Query("site_id"), 10, 64)
	if err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.SiteOwnedByUser(c.Request.Context(), siteID, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	items, err := h.service.ListPlacements(c.Request.Context(), siteID)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, items)
}

func (h *InventoryHandler) UpdatePlacement(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	principal, authenticated := CurrentPrincipal(c)
	owned, ownershipErr := h.service.PlacementOwnedByUser(c.Request.Context(), id, principal.UserID)
	if !authenticated || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	var item model.Placement
	if c.ShouldBindJSON(&item) != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	item.ID = id
	if err := h.service.UpdatePlacement(c.Request.Context(), &item); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, item)
}

func (h *InventoryHandler) DeletePlacement(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	principal, authenticated := CurrentPrincipal(c)
	owned, ownershipErr := h.service.PlacementOwnedByUser(c.Request.Context(), id, principal.UserID)
	if !authenticated || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	if err := h.service.DeletePlacement(c.Request.Context(), id); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}
