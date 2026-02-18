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
	var req model.Creative
	if err := c.ShouldBindJSON(&req); err != nil {
		HandleError(c, service.ErrInvalidInput)
		return
	}
	if err := h.service.Create(c.Request.Context(), &req); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusCreated, req)
}

func (h *CreativeHandler) Get(c *gin.Context) {
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	creative, err := h.service.GetByID(c.Request.Context(), id)
	if err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, creative)
}

func (h *CreativeHandler) Update(c *gin.Context) {
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
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

func (h *CreativeHandler) Delete(c *gin.Context) {
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	if err := h.service.Delete(c.Request.Context(), id); err != nil {
		HandleError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}
