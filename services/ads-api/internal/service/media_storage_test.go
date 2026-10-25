package service

import (
	"bytes"
	"encoding/base64"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func multipartFile(t *testing.T, name string, content []byte) *multipart.FileHeader {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("file", name)
	if err != nil {
		t.Fatalf("create multipart file: %v", err)
	}
	if _, err := part.Write(content); err != nil {
		t.Fatalf("write multipart file: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}
	request, err := http.NewRequest("POST", "/creatives/upload", &body)
	if err != nil {
		t.Fatalf("create request: %v", err)
	}
	request.Header.Set("Content-Type", writer.FormDataContentType())
	if err := request.ParseMultipartForm(1 << 20); err != nil {
		t.Fatalf("parse multipart form: %v", err)
	}
	return request.MultipartForm.File["file"][0]
}

func TestMediaStorageSavesImageAndVideoByDetectedContent(t *testing.T) {
	directory := t.TempDir()
	storage := NewMediaStorage(directory)
	png, err := base64.StdEncoding.DecodeString(
		"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
	)
	if err != nil {
		t.Fatalf("decode PNG: %v", err)
	}

	image, imagePath, err := storage.Save(multipartFile(t, "banner.txt", png))
	if err != nil {
		t.Fatalf("save image: %v", err)
	}
	if image.Type != "image" || image.MIMEType != "image/png" || filepath.Ext(imagePath) != ".png" {
		t.Fatalf("unexpected image metadata: %#v path=%s", image, imagePath)
	}
	saved, err := os.ReadFile(filepath.Join(directory, imagePath))
	if err != nil || !bytes.Equal(saved, png) {
		t.Fatalf("saved image differs: err=%v", err)
	}

	mp4 := []byte{0, 0, 0, 24, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm', 0, 0, 0, 0, 'i', 's', 'o', 'm', 'm', 'p', '4', '2'}
	video, videoPath, err := storage.Save(multipartFile(t, "clip.bin", mp4))
	if err != nil {
		t.Fatalf("save video: %v", err)
	}
	if video.Type != "video" || video.MIMEType != "video/mp4" || filepath.Ext(videoPath) != ".mp4" {
		t.Fatalf("unexpected video metadata: %#v path=%s", video, videoPath)
	}
}

func TestMediaStorageRejectsUnsupportedContent(t *testing.T) {
	storage := NewMediaStorage(t.TempDir())
	if _, _, err := storage.Save(multipartFile(t, "fake.png", []byte("not an image"))); err == nil {
		t.Fatal("unsupported content must be rejected")
	}
}
