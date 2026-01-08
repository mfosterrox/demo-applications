# https://github.com/HightechSec/web-ctf-container
FROM php:8.1-apache

LABEL maintainer="Foster <mfoster@redhat.com>"

# Install git for cloning
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

# Enable Apache mod_rewrite
RUN a2enmod rewrite

# Configure Apache to listen on port 8080 instead of 80 (for non-root user)
# Remove any existing Listen directives and create new ports.conf
RUN sed -i '/^Listen /d' /etc/apache2/ports.conf 2>/dev/null || true && \
    echo "Listen 8080" > /etc/apache2/ports.conf && \
    echo "<IfModule ssl_module>" >> /etc/apache2/ports.conf && \
    echo "    Listen 8443" >> /etc/apache2/ports.conf && \
    echo "</IfModule>" >> /etc/apache2/ports.conf

# Configure VirtualHost for port 8080
RUN rm -f /etc/apache2/sites-enabled/* && \
    echo "<VirtualHost *:8080>" > /etc/apache2/sites-available/000-default.conf && \
    echo "    ServerName localhost" >> /etc/apache2/sites-available/000-default.conf && \
    echo "    ServerAdmin webmaster@localhost" >> /etc/apache2/sites-available/000-default.conf && \
    echo "    DocumentRoot /var/www/html" >> /etc/apache2/sites-available/000-default.conf && \
    echo "    <Directory /var/www/html>" >> /etc/apache2/sites-available/000-default.conf && \
    echo "        Options Indexes FollowSymLinks" >> /etc/apache2/sites-available/000-default.conf && \
    echo "        AllowOverride All" >> /etc/apache2/sites-available/000-default.conf && \
    echo "        Require all granted" >> /etc/apache2/sites-available/000-default.conf && \
    echo "    </Directory>" >> /etc/apache2/sites-available/000-default.conf && \
    echo "    ErrorLog \${APACHE_LOG_DIR}/error.log" >> /etc/apache2/sites-available/000-default.conf && \
    echo "    CustomLog \${APACHE_LOG_DIR}/access.log combined" >> /etc/apache2/sites-available/000-default.conf && \
    echo "</VirtualHost>" >> /etc/apache2/sites-available/000-default.conf && \
    a2ensite 000-default.conf && \
    a2dissite 000-default.conf 2>/dev/null || true && \
    a2ensite 000-default.conf

# Add ServerName to apache2.conf to suppress warning
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Create a custom Apache startup script that forces port 8080
RUN echo '#!/bin/bash' > /usr/local/bin/apache2-foreground-8080 && \
    echo 'set -e' >> /usr/local/bin/apache2-foreground-8080 && \
    echo '# Force Apache to use port 8080' >> /usr/local/bin/apache2-foreground-8080 && \
    echo 'echo "Configuring Apache for port 8080..."' >> /usr/local/bin/apache2-foreground-8080 && \
    echo '# Remove any Listen 80 directives' >> /usr/local/bin/apache2-foreground-8080 && \
    echo 'sed -i "/^Listen 80$/d" /etc/apache2/ports.conf 2>/dev/null || true' >> /usr/local/bin/apache2-foreground-8080 && \
    echo '# Ensure Listen 8080 exists' >> /usr/local/bin/apache2-foreground-8080 && \
    echo 'grep -q "^Listen 8080" /etc/apache2/ports.conf || echo "Listen 8080" >> /etc/apache2/ports.conf' >> /usr/local/bin/apache2-foreground-8080 && \
    echo '# Update VirtualHost directives' >> /usr/local/bin/apache2-foreground-8080 && \
    echo 'sed -i "s/<VirtualHost \*:80>/<VirtualHost *:8080>/g" /etc/apache2/sites-enabled/*.conf 2>/dev/null || true' >> /usr/local/bin/apache2-foreground-8080 && \
    echo 'sed -i "s/:80>/:8080>/g" /etc/apache2/sites-enabled/*.conf 2>/dev/null || true' >> /usr/local/bin/apache2-foreground-8080 && \
    echo 'echo "Starting Apache on port 8080..."' >> /usr/local/bin/apache2-foreground-8080 && \
    echo 'exec apache2-foreground' >> /usr/local/bin/apache2-foreground-8080 && \
    chmod +x /usr/local/bin/apache2-foreground-8080

# Set working directory
WORKDIR /var/www/html

# Clone the repository
RUN git clone https://github.com/HightechSec/web-ctf-container.git /tmp/web-ctf && \
    cp -r /tmp/web-ctf/* /var/www/html/ && \
    rm -rf /tmp/web-ctf

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html

# Ensure Apache log directories are writable
RUN mkdir -p /var/log/apache2 && \
    chown -R www-data:www-data /var/log/apache2 && \
    chmod -R 755 /var/log/apache2

EXPOSE 8080

# Override CMD to use our custom script that ensures port 8080
CMD ["/usr/local/bin/apache2-foreground-8080"]

