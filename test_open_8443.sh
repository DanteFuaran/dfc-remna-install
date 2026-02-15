#!/bin/bash

# Load functions without executing main menu
source <(head -n -1 /opt/dev_dfc-remna-install/install_remnawave.sh)

# Call open_panel_access and capture output
{
    echo ""  # Simulate Enter key for prompts
} | open_panel_access

# Check result
if grep -q "# ─── 8443 Fallback" /opt/remnawave/nginx.conf; then
    echo "✅ SUCCESS: 8443 block was added"
    if ss -tuln | grep -q ":8443"; then
        echo "✅ SUCCESS: Port 8443 is listening"
    else
        echo "❌ FAIL: Port 8443 is not listening"
    fi
else
    echo "❌ FAIL: 8443 block was not added"
fi
