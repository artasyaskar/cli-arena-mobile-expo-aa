FROM node:20-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install global TypeScript
RUN npm install -g typescript

# Install Supabase CLI (using the correct architecture)
RUN curl -L "https://github.com/supabase/cli/releases/download/v2.30.4/supabase_2.30.4_linux_arm64.deb" -o supabase.deb \
    && dpkg -i supabase.deb \
    && rm supabase.deb

# Copy package files and install dependencies first for better caching
COPY package*.json ./

# Copy all source files before npm install so prepare/build scripts work
COPY . .

# Install dependencies (this will now work because source files are present)
RUN npm install

# Default command (optional)
CMD ["npm", "start"]