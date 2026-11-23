/***************************************************************************//**
 *   @file   adi_initialize.c
 *   @brief  Component init. Only sets up the pinmux.
 *   @author Lois Mathoi
********************************************************************************
 * Copyright 2026(c) Lois Mathoi
 *
 * SPDX-License-Identifier: BSD-3-Clause
*******************************************************************************/
#include "adi_initialize.h"

extern int32_t adi_initpinmux(void);

int32_t adi_initComponents(void)
{
	return adi_initpinmux();
}
