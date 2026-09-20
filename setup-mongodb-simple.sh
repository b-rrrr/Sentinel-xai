#!/bin/bash
# Quick MongoDB Setup for Sentinel Lab
# Run on MASTER node (192.168.1.17)
# This sets up MongoDB accessible from data-layer pods

set -e

echo "=== MongoDB Setup for Sentinel Lab ==="
echo ""

# Install MongoDB
sudo apt-get update
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
    sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/ubuntu jammy/mongodb/7.0 multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

sudo apt-get update
sudo apt-get install -y mongodb-org

# Start MongoDB
sudo systemctl start mongod
sudo systemctl enable mongod

# Wait a bit
sleep 3

# Create admin user
cat <<'EOF' | sudo mongosh --quiet
use admin
db.createUser({
    user: "admin",
    pwd: "CHANGE_THIS_PASSWORD",
    roles: [
        { role: "userAdminAnyDatabase", db: "admin" },
        { role: "dbAdminAnyDatabase", db: "admin" },
        { role: "readWriteAnyDatabase", db: "admin" }
    ]
});
EOF

# Enable remote access
sudo sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

# Restart mongod
sudo systemctl restart mongod

# Wait for MongoDB to be ready
sleep 3

# Verify MongoDB is running
sudo systemctl status mongod --no-pager | head -10

# Get connection string
echo ""
echo "MongoDB ready!"
echo "Connection string (change password!):"
echo "mongodb://admin:CHANGE_THIS_PASSWORD@192.168.1.17:27017/sentinel_lab"
echo ""
echo "Or with auth disabled (simpler):"
echo "mongodb://192.168.1.17:27017"
echo ""
echo "Test connection from this node:"
echo "mongosh mongodb://admin:CHANGE_THIS_PASSWORD@192.168.1.17:27017/admin"