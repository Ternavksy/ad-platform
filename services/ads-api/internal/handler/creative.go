package handler

import (
	"ads-api/internal/model"
	"ads-api/internal/service"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type CreativeHandler struct {
	service *service.CreativeService
}

func NewCreativeHandler(s *service.CreativeService) *CreativeHandler {
	return &CreativeHandler{service: s}
}

func (h *CreativeHandler) Create(c *gin.Context) {
	principal, ok := CurrentPrincipal(c)
	if !ok {
		HandleError(c, service.ErrForbidden)
		return
	}
	var req model.Creative
	if err := c.ShouldBindJSON(&req); err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	owned, ownershipErr := h.service.AdOwnedByUser(c.Request.Context(), req.AdID, principal.UserID)
	if ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	if err := h.service.Create(c.Request.Context(), &req); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusCreated, req)
}

func (h *CreativeHandler) Upload(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, service.MaxUploadRequestSize)
	adID, err := strconv.ParseInt(c.PostForm("ad_id"), 10, 64)
	if err != nil || adID <= 0 {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.AdOwnedByUser(c.Request.Context(), adID, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	file, err := c.FormFile("file")
	if err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	req := model.Creative{AdID: adID, Content: c.PostForm("content")}
	if err := h.service.CreateWithMedia(c.Request.Context(), &req, file); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusCreated, req)
}

func (h *CreativeHandler) List(c *gin.Context) {
	adID, err := strconv.ParseInt(c.Query("ad_id"), 10, 64)
	if err != nil || adID <= 0 {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.AdOwnedByUser(c.Request.Context(), adID, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	items, err := h.service.ListByAd(c.Request.Context(), adID)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, items)
}

func (h *CreativeHandler) Get(c *gin.Context) {
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.OwnedByUser(c.Request.Context(), id, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	creative, err := h.service.GetByID(c.Request.Context(), id)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, creative)
}

func (h *CreativeHandler) Update(c *gin.Context) {
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.OwnedByUser(c.Request.Context(), id, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	var req model.Creative
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

func (h *CreativeHandler) UpdateUpload(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, service.MaxUploadRequestSize)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		HandleError(c, service.ErrNotFound)
		return
	}
	principal, ok := CurrentPrincipal(c)
	owned, ownershipErr := h.service.OwnedByUser(c.Request.Context(), id, principal.UserID)
	if !ok || ownershipErr != nil || !owned {
		HandleError(c, service.ErrForbidden)
		return
	}
	file, err := c.FormFile("file")
	if err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	req := model.Creative{ID: id, Content: c.PostForm("content")}
	if err := h.service.UpdateWithMedia(c.Request.Context(), &req, file); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, req)
}

func (h *CreativeHandler) Delete(c *gin.Context) {
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

func (h *CreativeHandler) SubmitForModeration(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	principal, ok := CurrentPrincipal(c)
	if err != nil || id <= 0 || !ok {
		HandleError(c, service.ErrNotFound)
		return
	}
	creative, err := h.service.SubmitForModeration(
		c.Request.Context(),
		id,
		principal.UserID,
		principal.HasPermission("moderation.review"),
	)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, creative)
}

func (h *CreativeHandler) ListModeration(c *gin.Context) {
	items, err := h.service.ListForModeration(c.Request.Context(), c.Query("status"))
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, items)
}

func (h *CreativeHandler) ReviewModeration(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	principal, ok := CurrentPrincipal(c)
	if err != nil || id <= 0 || !ok {
		HandleError(c, service.ErrNotFound)
		return
	}
	var decision model.ModerationDecision
	if err := c.ShouldBindJSON(&decision); err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	creative, err := h.service.ReviewModeration(
		c.Request.Context(),
		id,
		principal.UserID,
		decision,
	)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, creative)
}
