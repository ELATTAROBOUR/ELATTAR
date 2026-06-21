FROM dart:stable

WORKDIR /app

# Copy pubspec files and resolve dependencies
COPY pubspec.* ./
RUN dart pub get

# Copy the rest of the application
COPY . .

# Expose the port the server runs on
EXPOSE 8080

# Start the server
CMD ["dart", "run", "bin/server.dart"]
