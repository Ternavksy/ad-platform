package service

import "errors"

var (
	ErrNotFound     = errors.New("not found")
	ErrForbidden    = errors.New("forbidden")
	ErrInvalidInput = errors.New("Invalid input")
	ErrInternal     = errors.New("internal error")
)
