package service

import "errors"

var (
	ErrNotFound     = errors.New("not found")
	ErrForbidden    = errors.New("forbidden")
	ErrConflict     = errors.New("conflict")
	ErrInvalidInput = errors.New("Invalid input")
	ErrInternal     = errors.New("internal error")
	ErrNoDelivery   = errors.New("no eligible ad")
)
