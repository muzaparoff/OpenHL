// SPDX-License-Identifier: MIT

// HyperliquidAPI — REST and WebSocket client for api.hyperliquid.xyz.
// Depends on OpenHLCore for shared types.
//
// Phase 1 public API surface is split across:
//   - HyperliquidClient.swift          the protocol view models depend on
//   - HyperliquidError.swift           the typed error enum
//   - URLSessionHyperliquidClient.swift production implementation
//   - DTOs/InfoRequest.swift           POST /info request body
//   - DTOs/ClearinghouseStateDTO.swift wire-shaped response types
//   - DomainModels.swift               domain types view models bind to
//   - AddressStore.swift               persistence protocol + impls
//
// This file retains only the module version constant.

/// The current semantic version of the HyperliquidAPI package.
/// Bumped alongside the app version; used in tests as a minimal
/// compile-time proof that the module is reachable.
public let hyperliquidAPIVersion: String = "0.0.0"
