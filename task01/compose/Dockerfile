FROM php:8.3-apache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Install MySQL extensions
RUN docker-php-ext-install mysqli pdo pdo_mysql

# Enable Apache mod_rewrite and ssl
RUN a2enmod rewrite ssl headers

# Set working directory
WORKDIR /var/www/html

# Expose ports 80,443
EXPOSE 80
EXPOSE 443