import CoreGraphics
import Foundation

enum RecordingHotkey: String, Codable, CaseIterable, Identifiable {
    case rightCommand
    case function
    case rightOption
    case rightControl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rightCommand: return "Right Command"
        case .function:     return "Fn"
        case .rightOption:  return "Right Option"
        case .rightControl: return "Right Control"
        }
    }

    var shortLabel: String {
        switch self {
        case .rightCommand: return "R⌘"
        case .function:     return "Fn"
        case .rightOption:  return "R⌥"
        case .rightControl: return "R⌃"
        }
    }

    var systemImage: String {
        switch self {
        case .rightCommand: return "command"
        case .function:     return "keyboard"
        case .rightOption:  return "option"
        case .rightControl: return "control"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .rightCommand: return 0x36
        case .function:     return 0x3F
        case .rightOption:  return 0x3D
        case .rightControl: return 0x3E
        }
    }

    var pressedFlag: CGEventFlags {
        switch self {
        case .rightCommand: return .maskCommand
        case .function:     return .maskSecondaryFn
        case .rightOption:  return .maskAlternate
        case .rightControl: return .maskControl
        }
    }

    static func fromLegacyKeyCode(_ keyCode: UInt16) -> RecordingHotkey? {
        switch keyCode {
        case 0x36: return .rightCommand
        case 0x3F: return .function
        case 0x3D: return .rightOption
        case 0x3E: return .rightControl
        default:   return nil
        }
    }
}
