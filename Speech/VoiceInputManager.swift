import Foundation
import Speech
import AVFoundation

struct ParsedVoiceInput {
    var itemName: String
    var locationDescription: String
    var rawTranscript: String
}

protocol VoiceInputManagerDelegate: AnyObject {
    func voiceInputManager(_ manager: VoiceInputManager, didReceiveTranscript transcript: String)
    func voiceInputManager(_ manager: VoiceInputManager, didParseInput input: ParsedVoiceInput)
    func voiceInputManager(_ manager: VoiceInputManager, didFailWithError error: Error)
    func voiceInputManagerDidStartListening(_ manager: VoiceInputManager)
    func voiceInputManagerDidStopListening(_ manager: VoiceInputManager)
}

final class VoiceInputManager: ObservableObject {
    static let shared = VoiceInputManager()
    
    @Published var isAuthorized = false
    @Published var isMicrophoneAuthorized = false
    @Published var isListening = false
    @Published var currentTranscript = ""
    @Published var authorizationError: String?
    
    var onResult: ((String) -> Void)?
    
    weak var delegate: VoiceInputManagerDelegate?
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private let itemKeywords = ["my", "the", "a", "an"]
    private let locationKeywords = ["in", "at", "on", "near", "under", "behind", "inside", "outside"]
    
    private init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    func requestAuthorization() async -> Bool {
        async let speechStatus: Void = requestSpeechAuthorization()
        async let micStatus: Void = requestMicrophoneAuthorization()
        
        await speechStatus
        await micStatus
        
        return isAuthorized && isMicrophoneAuthorized
    }
    
    private func requestSpeechAuthorization() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    self?.isAuthorized = (status == .authorized)
                    if status != .authorized {
                        self?.authorizationError = "Speech recognition not authorized. Please enable in Settings."
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func requestMicrophoneAuthorization() async {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.isMicrophoneAuthorized = granted
                    if !granted {
                        self.authorizationError = "Microphone access denied. Please enable in Settings."
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    func startListening() throws {
        guard !authorizationError.isEmptyOrNil else {
            if !isAuthorized {
                throw VoiceInputError.notAuthorized
            }
            if !isMicrophoneAuthorized {
                throw VoiceInputError.microphoneNotAuthorized
            }
            throw VoiceInputError.notAuthorized
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceInputError.recognizerNotAvailable
        }
        
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[VoiceInputManager] Audio session setup failed: \(error)")
            throw VoiceInputError.audioSessionFailed
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceInputError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 else {
            throw VoiceInputError.audioSessionFailed
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("[VoiceInputManager] Audio engine failed to start: \(error)")
            inputNode.removeTap(onBus: 0)
            throw VoiceInputError.audioSessionFailed
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcript = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.currentTranscript = transcript
                    self.delegate?.voiceInputManager(self, didReceiveTranscript: transcript)
                    self.onResult?(transcript)
                    
                    if result.isFinal {
                        let parsedInput = self.parseTranscript(transcript)
                        self.delegate?.voiceInputManager(self, didParseInput: parsedInput)
                    }
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.delegate?.voiceInputManager(self, didFailWithError: error)
                    self.stopListening()
                }
            }
        }
        
        DispatchQueue.main.async {
            self.isListening = true
            self.delegate?.voiceInputManagerDidStartListening(self)
        }
    }
    
    func stopListening() {
        guard isListening else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.isListening = false
            if let self = self {
                self.delegate?.voiceInputManagerDidStopListening(self)
            }
        }
    }
    
    func parseTranscript(_ transcript: String) -> ParsedVoiceInput {
        let words = transcript.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        var itemName = ""
        var locationDescription = ""
        
        var locationKeywordIndex: Int?
        
        for (index, word) in words.enumerated() {
            if locationKeywords.contains(word) {
                locationKeywordIndex = index
                break
            }
        }
        
        if let locIndex = locationKeywordIndex {
            let itemWords = words[0..<locIndex].filter { !itemKeywords.contains($0) }
            itemName = itemWords.joined(separator: " ")
            
            let locationWords = words[(locIndex + 1)...].filter { !itemKeywords.contains($0) && !locationKeywords.contains($0) }
            locationDescription = locationWords.joined(separator: " ")
        } else {
            let itemWords = words.filter { !itemKeywords.contains($0) }
            itemName = itemWords.joined(separator: " ")
        }
        
        return ParsedVoiceInput(
            itemName: itemName.trimmingCharacters(in: .whitespaces),
            locationDescription: locationDescription.trimmingCharacters(in: .whitespaces),
            rawTranscript: transcript
        )
    }
    
    func transcribeAudioFile(url: URL) async throws -> String {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceInputError.recognizerNotAvailable
        }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        
        return try await withCheckedThrowingContinuation { continuation in
            speechRecognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result, result.isFinal else { return }
                
                let transcript = result.bestTranscription.formattedString
                continuation.resume(returning: transcript)
            }
        }
    }
}

enum VoiceInputError: LocalizedError {
    case notAuthorized
    case microphoneNotAuthorized
    case recognizerNotAvailable
    case requestCreationFailed
    case audioSessionFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable in Settings."
        case .microphoneNotAuthorized:
            return "Microphone access denied. Please enable in Settings."
        case .recognizerNotAvailable:
            return "Speech recognizer not available"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        case .audioSessionFailed:
            return "Failed to configure audio session"
        }
    }
}

private extension Optional where Wrapped == String {
    var isEmptyOrNil: Bool {
        return self?.isEmpty ?? true
    }
}
