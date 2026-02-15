#!/bin/bash

# Load all functions but don't call main_menu
source <(sed '$d' /opt/dev_dfc-remna-install/install_remnawave.sh)

# Test open_panel_access
open_panel_access
