# Use official Bun image as the base
FROM oven/bun:1.1-alpine

# Set working directory
WORKDIR /app

# Copy package files and lockfile
COPY package.json bun.lockb ./

# Install dependencies (frozen lockfile to ensure reproducible builds)
RUN bun install --frozen-lockfile

# Copy the rest of the application files
COPY . .

# Set environment to production
ENV NODE_ENV=production

# Build the Next.js application
RUN bun run build

# Expose port 3000
EXPOSE 3000

# Set user to a non-root user for security (user 'bun' has UID 1000 in this image)
USER bun

# Run the app
CMD ["bun", "run", "start"]
