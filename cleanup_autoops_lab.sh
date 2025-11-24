#!/bin/bash

set -e

echo "============================================================"
echo "AutoOps VM Cleanup Script"
echo "============================================================"
echo ""

VM_NAME="autoops"

# Check if VM exists
if ! multipass list | grep -q "$VM_NAME"; then
    echo "✓ VM '$VM_NAME' does not exist. Nothing to clean up."
    exit 0
fi

echo "Found VM: $VM_NAME"
echo ""

# Show VM info
echo "Current VM status:"
multipass info $VM_NAME
echo ""

# Confirm cleanup
read -p "Do you want to delete the '$VM_NAME' VM? This will remove all data. (y/n): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "✗ Cleanup cancelled by user"
    exit 0
fi

echo "🗑️  Stopping VM '$VM_NAME'..."
multipass stop $VM_NAME 2>/dev/null || echo "VM already stopped"

echo "🗑️  Deleting VM '$VM_NAME'..."
multipass delete $VM_NAME

echo "🗑️  Purging deleted VMs..."
multipass purge

echo ""
echo "✓ VM '$VM_NAME' has been completely removed!"
echo ""

# Show remaining VMs
echo "Remaining VMs:"
multipass list
echo ""
echo "Cleanup complete!"