#!/bin/bash
set -e

echo "Stopping Traccar..."
sudo systemctl stop traccar

echo "Building frontend..."
cd traccar-web
npm run build
sudo cp -r build/* /opt/traccar/web/

echo "Building backend..."
cd ..
./gradlew assemble
sudo cp -r target/lib/* /opt/traccar/lib/
sudo cp target/tracker-server.jar /opt/traccar/tracker-server.jar

echo "Restarting Traccar..."
sudo systemctl restart traccar

echo "Done!"