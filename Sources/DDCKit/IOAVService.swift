//  IOAVService.swift
//  DDCKit
//
//  Bindings to the IOAVService I2C API on Apple Silicon.
//
//  These functions are *exported by the public IOKit framework* (verified in
//  MacOSX.sdk IOKit.tbd) but have no public header — they are the same
//  interface used by MonitorControl, Lunar, BetterDisplay and m1ddc.
//  On Apple Silicon, each external display's DDC/CI channel is represented
//  by a `DCPAVServiceProxy` node in the IORegistry with `Location = External`;
//  `IOAVServiceCreateWithService` opens that node and returns an opaque
//  `IOAVServiceRef` (a CF object) that can perform raw I2C transactions on
//  the display's DDC bus.

import Foundation
import IOKit

/// Opaque CF object representing an AV service (DDC channel) for one display.
typealias IOAVServiceRef = CFTypeRef

/// Creates an AV service from a `DCPAVServiceProxy` IORegistry entry.
/// Returns a +1 retained CF object, or nil if the service cannot be opened.
@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(
    _ allocator: CFAllocator?,
    _ service: io_service_t
) -> Unmanaged<CFTypeRef>?

/// Copies the raw EDID of the display behind this AV service.
@_silgen_name("IOAVServiceCopyEDID")
func IOAVServiceCopyEDID(
    _ service: IOAVServiceRef,
    _ edid: UnsafeMutablePointer<Unmanaged<CFData>?>
) -> IOReturn

/// Reads `outputBufferSize` bytes from I2C `chipAddress` at register `offset`.
@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ outputBuffer: UnsafeMutableRawPointer,
    _ outputBufferSize: UInt32
) -> IOReturn

/// Writes `inputBufferSize` bytes to I2C `chipAddress` at register `dataAddress`.
@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ inputBuffer: UnsafeRawPointer,
    _ inputBufferSize: UInt32
) -> IOReturn
