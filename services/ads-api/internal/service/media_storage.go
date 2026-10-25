package service

import (
	"ads-api/internal/model"
	"bytes"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
)

const (
	MaxImageSize         int64 = 10 << 20
	MaxVideoSize         int64 = 100 << 20
	MaxUploadRequestSize       = MaxVideoSize + (1 << 20)
)

type mediaRule struct {
	mediaType string
	extension string
	maxSize   int64
}

var allowedMedia = map[string]mediaRule{
	"image/jpeg":      {mediaType: "image", extension: ".jpg", maxSize: MaxImageSize},
	"image/png":       {mediaType: "image", extension: ".png", maxSize: MaxImageSize},
	"image/gif":       {mediaType: "image", extension: ".gif", maxSize: MaxImageSize},
	"image/webp":      {mediaType: "image", extension: ".webp", maxSize: MaxImageSize},
	"video/mp4":       {mediaType: "video", extension: ".mp4", maxSize: MaxVideoSize},
	"video/webm":      {mediaType: "video", extension: ".webm", maxSize: MaxVideoSize},
	"video/quicktime": {mediaType: "video", extension: ".mov", maxSize: MaxVideoSize},
}

type MediaStorage struct {
	directory string
}

func NewMediaStorage(directory string) *MediaStorage {
	return &MediaStorage{directory: directory}
}

func (s *MediaStorage) Save(header *multipart.FileHeader) (model.CreativeMedia, string, error) {
	if header == nil || header.Size <= 0 || header.Size > MaxVideoSize {
		return model.CreativeMedia{}, "", fmt.Errorf("media file is empty or too large: %w", ErrInvalidInput)
	}
	source, err := header.Open()
	if err != nil {
		return model.CreativeMedia{}, "", fmt.Errorf("open media: %w", err)
	}
	defer source.Close()

	head := make([]byte, 512)
	read, readErr := io.ReadFull(source, head)
	if readErr != nil && readErr != io.ErrUnexpectedEOF {
		return model.CreativeMedia{}, "", fmt.Errorf("read media: %w", ErrInvalidInput)
	}
	mimeType := http.DetectContentType(head[:read])
	rule, ok := allowedMedia[mimeType]
	if !ok {
		return model.CreativeMedia{}, "", fmt.Errorf("unsupported media type %s: %w", mimeType, ErrInvalidInput)
	}
	if header.Size > rule.maxSize {
		return model.CreativeMedia{}, "", fmt.Errorf("%s exceeds the size limit: %w", rule.mediaType, ErrInvalidInput)
	}
	if err := os.MkdirAll(s.directory, 0o750); err != nil {
		return model.CreativeMedia{}, "", fmt.Errorf("create media directory: %w", err)
	}

	storedName := uuid.NewString() + rule.extension
	storedPath := filepath.Join(s.directory, storedName)
	destination, err := os.OpenFile(storedPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o640)
	if err != nil {
		return model.CreativeMedia{}, "", fmt.Errorf("create media file: %w", err)
	}
	written, copyErr := io.Copy(destination, io.MultiReader(bytes.NewReader(head[:read]), source))
	closeErr := destination.Close()
	if copyErr != nil || closeErr != nil || written <= 0 || written > rule.maxSize {
		_ = os.Remove(storedPath)
		return model.CreativeMedia{}, "", fmt.Errorf("save media file: %w", ErrInvalidInput)
	}

	originalName := strings.TrimSpace(filepath.Base(header.Filename))
	originalName = strings.ToValidUTF8(originalName, "")
	originalRunes := []rune(originalName)
	if len(originalRunes) > 255 {
		originalName = string(originalRunes[:255])
	}
	media := model.CreativeMedia{
		Type:     rule.mediaType,
		URL:      "/media/" + storedName,
		MIMEType: mimeType,
		FileName: originalName,
		FileSize: written,
	}
	return media, storedName, nil
}

func (s *MediaStorage) Remove(storedName string) error {
	if storedName == "" {
		return nil
	}
	if filepath.Base(storedName) != storedName {
		return fmt.Errorf("invalid media path")
	}
	err := os.Remove(filepath.Join(s.directory, storedName))
	if os.IsNotExist(err) {
		return nil
	}
	return err
}
