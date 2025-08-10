/**
 * XSS Protection Utilities for Frontend
 * Comprehensive Cross-Site Scripting prevention for React/Next.js
 */

import DOMPurify from 'dompurify';
import { escape } from 'lodash';

export interface XSSProtectionConfig {
  allowedTags?: string[];
  allowedAttributes?: { [key: string]: string[] };
  allowedSchemes?: string[];
  stripIgnoreTag?: boolean;
  stripIgnoreTagBody?: boolean;
}

export class XSSProtection {
  private static defaultConfig: XSSProtectionConfig = {
    allowedTags: [
      'p', 'br', 'strong', 'em', 'u', 's', 'i', 'b',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'ul', 'ol', 'li', 'blockquote',
      'a', 'img', 'table', 'thead', 'tbody', 'tr', 'td', 'th'
    ],
    allowedAttributes: {
      'a': ['href', 'title', 'target'],
      'img': ['src', 'alt', 'width', 'height'],
      '*': ['class', 'id']
    },
    allowedSchemes: ['http', 'https', 'mailto', 'tel'],
    stripIgnoreTag: true,
    stripIgnoreTagBody: true
  };

  /**
   * Sanitize HTML content to prevent XSS attacks
   */
  public static sanitizeHTML(
    html: string, 
    config: XSSProtectionConfig = {}
  ): string {
    if (!html || typeof html !== 'string') {
      return '';
    }

    const finalConfig = { ...this.defaultConfig, ...config };

    // Configure DOMPurify
    const purifyConfig = {
      ALLOWED_TAGS: finalConfig.allowedTags,
      ALLOWED_ATTR: Object.keys(finalConfig.allowedAttributes || {}).reduce(
        (attrs, tag) => {
          const tagAttrs = finalConfig.allowedAttributes?.[tag] || [];
          const universalAttrs = finalConfig.allowedAttributes?.['*'] || [];
          return [...attrs, ...tagAttrs, ...universalAttrs];
        },
        [] as string[]
      ),
      ALLOWED_URI_REGEXP: new RegExp(
        `^(?:(?:${(finalConfig.allowedSchemes || []).join('|')}):)`,
        'i'
      ),
      KEEP_CONTENT: !finalConfig.stripIgnoreTagBody,
      RETURN_DOM: false,
      RETURN_DOM_FRAGMENT: false,
      RETURN_DOM_IMPORT: false,
      SANITIZE_DOM: true,
      WHOLE_DOCUMENT: false,
      IN_PLACE: false
    };

    try {
      return DOMPurify.sanitize(html, purifyConfig);
    } catch (error) {
      console.error('XSS sanitization failed:', error);
      return '';
    }
  }

  /**
   * Escape HTML entities in plain text
   */
  public static escapeHTML(text: string): string {
    if (!text || typeof text !== 'string') {
      return '';
    }

    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#x27;')
      .replace(/\//g, '&#x2F;');
  }

  /**
   * Validate and sanitize URL to prevent javascript: and data: URLs
   */
  public static sanitizeURL(url: string): string {
    if (!url || typeof url !== 'string') {
      return '';
    }

    // Remove any whitespace and control characters
    const cleanURL = url.trim().replace(/[\x00-\x1f\x7f-\x9f]/g, '');

    // Check for dangerous protocols
    const dangerousProtocols = [
      'javascript:',
      'data:',
      'vbscript:',
      'file:',
      'ftp:'
    ];

    const lowerURL = cleanURL.toLowerCase();
    
    for (const protocol of dangerousProtocols) {
      if (lowerURL.startsWith(protocol)) {
        console.warn(`Dangerous URL protocol detected: ${protocol}`);
        return '';
      }
    }

    // Allow relative URLs, http, https, mailto, tel
    const allowedProtocolPattern = /^(?:https?:\/\/|mailto:|tel:|\/|\.\/|#)/i;
    
    if (!allowedProtocolPattern.test(cleanURL)) {
      console.warn(`Invalid URL protocol: ${cleanURL}`);
      return '';
    }

    return cleanURL;
  }

  /**
   * Validate and sanitize CSS to prevent CSS injection
   */
  public static sanitizeCSS(css: string): string {
    if (!css || typeof css !== 'string') {
      return '';
    }

    // Remove dangerous CSS properties and values
    const dangerousPatterns = [
      /expression\s*\(/gi,
      /javascript:/gi,
      /vbscript:/gi,
      /data:/gi,
      /binding:/gi,
      /behavior:/gi,
      /@import/gi,
      /url\s*\(\s*["']?\s*javascript:/gi,
      /url\s*\(\s*["']?\s*data:/gi
    ];

    let sanitizedCSS = css;
    
    for (const pattern of dangerousPatterns) {
      sanitizedCSS = sanitizedCSS.replace(pattern, '');
    }

    return sanitizedCSS;
  }

  /**
   * Validate and sanitize user input for display
   */
  public static sanitizeUserInput(
    input: string, 
    type: 'text' | 'html' | 'url' | 'css' = 'text'
  ): string {
    if (!input || typeof input !== 'string') {
      return '';
    }

    switch (type) {
      case 'html':
        return this.sanitizeHTML(input);
      case 'url':
        return this.sanitizeURL(input);
      case 'css':
        return this.sanitizeCSS(input);
      case 'text':
      default:
        return this.escapeHTML(input);
    }
  }

  /**
   * Create a secure Content Security Policy
   */
  public static generateCSP(config: {
    allowInlineStyles?: boolean;
    allowInlineScripts?: boolean;
    allowedDomains?: string[];
    allowedImageSources?: string[];
    reportURI?: string;
  } = {}): string {
    const {
      allowInlineStyles = false,
      allowInlineScripts = false,
      allowedDomains = [],
      allowedImageSources = [],
      reportURI
    } = config;

    const directives: string[] = [
      "default-src 'self'",
      `script-src 'self'${allowInlineScripts ? " 'unsafe-inline'" : ''} ${allowedDomains.join(' ')}`.trim(),
      `style-src 'self'${allowInlineStyles ? " 'unsafe-inline'" : ''} https://fonts.googleapis.com`.trim(),
      `img-src 'self' data: https: ${allowedImageSources.join(' ')}`.trim(),
      "font-src 'self' https://fonts.gstatic.com",
      "connect-src 'self' wss: https:",
      "media-src 'self'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
      "upgrade-insecure-requests"
    ];

    if (reportURI) {
      directives.push(`report-uri ${reportURI}`);
    }

    return directives.join('; ');
  }
}

/**
 * React Hook for XSS Protection
 */
export function useXSSProtection() {
  const sanitizeHTML = (html: string, config?: XSSProtectionConfig) => 
    XSSProtection.sanitizeHTML(html, config);

  const escapeHTML = (text: string) => 
    XSSProtection.escapeHTML(text);

  const sanitizeURL = (url: string) => 
    XSSProtection.sanitizeURL(url);

  const sanitizeUserInput = (input: string, type?: 'text' | 'html' | 'url' | 'css') => 
    XSSProtection.sanitizeUserInput(input, type);

  return {
    sanitizeHTML,
    escapeHTML,
    sanitizeURL,
    sanitizeUserInput
  };
}

/**
 * Safe innerHTML component for React
 */
import React from 'react';

interface SafeHTMLProps {
  html: string;
  config?: XSSProtectionConfig;
  className?: string;
  tag?: keyof JSX.IntrinsicElements;
}

export const SafeHTML: React.FC<SafeHTMLProps> = ({ 
  html, 
  config, 
  className, 
  tag: Tag = 'div' 
}) => {
  const sanitizedHTML = XSSProtection.sanitizeHTML(html, config);
  
  return (
    <Tag 
      className={className}
      dangerouslySetInnerHTML={{ __html: sanitizedHTML }}
    />
  );
};

/**
 * Safe Link component for React
 */
interface SafeLinkProps extends React.AnchorHTMLAttributes<HTMLAnchorElement> {
  href: string;
  children: React.ReactNode;
  external?: boolean;
}

export const SafeLink: React.FC<SafeLinkProps> = ({ 
  href, 
  children, 
  external = false,
  ...props 
}) => {
  const sanitizedHref = XSSProtection.sanitizeURL(href);
  
  if (!sanitizedHref) {
    console.warn(`Blocked unsafe link: ${href}`);
    return <span>{children}</span>;
  }

  const linkProps: React.AnchorHTMLAttributes<HTMLAnchorElement> = {
    ...props,
    href: sanitizedHref
  };

  if (external && (sanitizedHref.startsWith('http://') || sanitizedHref.startsWith('https://'))) {
    linkProps.target = '_blank';
    linkProps.rel = 'noopener noreferrer';
  }

  return <a {...linkProps}>{children}</a>;
};

/**
 * Input validation functions
 */
export class InputValidator {
  private static emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
  private static phoneRegex = /^[\+]?[1-9][\d]{0,15}$/;
  private static urlRegex = /^https?:\/\/(?:[-\w.])+(?:\:[0-9]+)?(?:\/(?:[\w\/_.])*(?:\?(?:[\w&=%.])*)?(?:\#(?:[\w.])*)?)?$/;

  public static validateEmail(email: string): boolean {
    return this.emailRegex.test(email);
  }

  public static validatePhone(phone: string): boolean {
    return this.phoneRegex.test(phone.replace(/\s/g, ''));
  }

  public static validateURL(url: string): boolean {
    return this.urlRegex.test(url);
  }

  public static validateString(
    input: string, 
    options: {
      minLength?: number;
      maxLength?: number;
      allowEmpty?: boolean;
      pattern?: RegExp;
    } = {}
  ): { valid: boolean; error?: string } {
    const { minLength = 0, maxLength = 10000, allowEmpty = false, pattern } = options;

    if (!input && !allowEmpty) {
      return { valid: false, error: 'Input is required' };
    }

    if (input && input.length < minLength) {
      return { valid: false, error: `Input must be at least ${minLength} characters` };
    }

    if (input && input.length > maxLength) {
      return { valid: false, error: `Input must not exceed ${maxLength} characters` };
    }

    if (pattern && !pattern.test(input)) {
      return { valid: false, error: 'Input format is invalid' };
    }

    return { valid: true };
  }
}

/**
 * Secure form data handler
 */
export function sanitizeFormData(formData: Record<string, any>): Record<string, any> {
  const sanitizedData: Record<string, any> = {};

  for (const [key, value] of Object.entries(formData)) {
    if (typeof value === 'string') {
      sanitizedData[key] = XSSProtection.sanitizeUserInput(value, 'text');
    } else if (Array.isArray(value)) {
      sanitizedData[key] = value.map(item => 
        typeof item === 'string' 
          ? XSSProtection.sanitizeUserInput(item, 'text')
          : item
      );
    } else {
      sanitizedData[key] = value;
    }
  }

  return sanitizedData;
}

/**
 * Secure localStorage wrapper
 */
export class SecureStorage {
  private static encrypt(data: string): string {
    // Simple obfuscation - in production, use proper encryption
    return btoa(data);
  }

  private static decrypt(data: string): string {
    try {
      return atob(data);
    } catch {
      return '';
    }
  }

  public static setItem(key: string, value: any): void {
    try {
      const sanitizedKey = XSSProtection.escapeHTML(key);
      const stringValue = typeof value === 'string' ? value : JSON.stringify(value);
      const sanitizedValue = XSSProtection.sanitizeUserInput(stringValue, 'text');
      const encryptedValue = this.encrypt(sanitizedValue);
      
      localStorage.setItem(sanitizedKey, encryptedValue);
    } catch (error) {
      console.error('SecureStorage setItem failed:', error);
    }
  }

  public static getItem(key: string): string | null {
    try {
      const sanitizedKey = XSSProtection.escapeHTML(key);
      const encryptedValue = localStorage.getItem(sanitizedKey);
      
      if (!encryptedValue) {
        return null;
      }

      return this.decrypt(encryptedValue);
    } catch (error) {
      console.error('SecureStorage getItem failed:', error);
      return null;
    }
  }

  public static removeItem(key: string): void {
    try {
      const sanitizedKey = XSSProtection.escapeHTML(key);
      localStorage.removeItem(sanitizedKey);
    } catch (error) {
      console.error('SecureStorage removeItem failed:', error);
    }
  }
}

export default XSSProtection;