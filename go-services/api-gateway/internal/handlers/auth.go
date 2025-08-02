package handlers

import (
	"fmt"
	"net/http"
	
	"github.com/Reg-Kris/pyairtable-api-gateway/internal/config"
	"github.com/gofiber/fiber/v2"
	"go.uber.org/zap"
)

type AuthHandler struct {
	config *config.Config
	proxy  *ProxyHandler
}

func NewAuthHandler(config *config.Config, httpClient *http.Client, logger *zap.Logger) *AuthHandler {
	return &AuthHandler{
		config: config,
		proxy:  NewProxyHandler(httpClient, logger),
	}
}

func (h *AuthHandler) Login(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/auth/login", h.config.AuthServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AuthHandler) Register(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/auth/register", h.config.AuthServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AuthHandler) RefreshToken(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/auth/refresh", h.config.AuthServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}

func (h *AuthHandler) Logout(c *fiber.Ctx) error {
	targetURL := fmt.Sprintf("%s/auth/logout", h.config.AuthServiceURL)
	return h.proxy.ProxyRequest(c, targetURL)
}