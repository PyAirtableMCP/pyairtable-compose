# PyAirtable Chat UI

A modern, responsive chat interface built with React, Vite, TypeScript, and shadcn/ui. This frontend provides an intuitive ChatGPT/Claude-like experience for interacting with your PyAirtable data and AI assistants.

## Features

- 🎨 **Modern Design**: Built with shadcn/ui components and Tailwind CSS
- 🌙 **Dark/Light Mode**: Toggle between themes with persistent preference
- 💬 **Real-time Chat**: WebSocket connection for instant message delivery
- 📁 **File Upload**: Drag & drop or click to upload files and documents
- 🎙️ **Voice Messages**: Record and send voice messages (optional)
- 📱 **Responsive**: Works perfectly on desktop and mobile devices
- ⚡ **Fast**: Built with Vite for lightning-fast development and builds
- 🔒 **Secure**: JWT authentication with secure token storage
- 🔄 **Auto-reconnect**: Automatic reconnection when network drops

## Quick Start

### Development
```bash
npm install
npm run dev
```
Visit [http://localhost:5173](http://localhost:5173)

### Docker
```bash
docker-compose -f docker-compose.dev.yml up --build
```
Visit [http://localhost:5174](http://localhost:5174)

## Technology Stack

- React 19 + TypeScript
- Vite (build tool)
- shadcn/ui + Tailwind CSS
- Lucide React (icons)
- WebSocket for real-time messaging

## Project Structure

```
src/
├── components/
│   ├── chat/              # Chat-specific components
│   └── ui/                # shadcn/ui components
├── pages/                 # Authentication pages
├── lib/                   # API client and utilities
└── App.tsx               # Main application
```

## Environment Variables

Copy `.env.example` to `.env` and configure:

```env
VITE_API_BASE_URL=http://localhost:7000
VITE_WS_BASE_URL=ws://localhost:7000
VITE_ENABLE_FILE_UPLOAD=true
VITE_ENABLE_DARK_MODE=true
```