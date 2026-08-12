/*
 * Copyright (C) 2026 The Android Open Source Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef _BDROID_BUILDCFG_H
#define _BDROID_BUILDCFG_H

#define BTM_DEF_LOCAL_NAME "K3 Pico-ITX"

// Bluetooth class of device
#define BTA_DM_COD {0x00, 0x04, 0x24}

// Enable HFP Wide Band Speech
#define BTIF_HF_WBS_PREFERRED TRUE

// SSP debug mode
#define BTM_SSP_DEBUG_MODE FALSE

// Page timeout
#define BTM_DEFAULT_INQUIRY_MODE BTM_GENERAL_INQUIRY

// Max connections
#define BTM_MAX_SCO_LINKS 2

// A2DP sink configuration
#define BTA_AV_SINK_INCLUDED TRUE

#endif
