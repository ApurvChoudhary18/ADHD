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
    @Published var isAuthorized = false
    @Published var isListening = false
    @Published var currentTranscript = ""
    
    var onResult: ((String) -> Void)?
    
    weak var delegate: VoiceInputManagerDelegate?
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private let itemKeywords = ["my", "the", "a", "an"]
    private let locationKeywords = ["in", "at", "on", "near", "under", "behind", "inside", "outside"]
    
    init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    func requestAuthorization() async {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.isAuthorized = (status == .authorized)
                    continuation.resume()
                }
            }
        }
    }
    
    func startListening() throws {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceInputError.recognizerNotAvailable
        }
        
        guard isAuthorized else {
            throw VoiceInputError.notAuthorized
        }
        
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceInputError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
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
                }
            }
        }
        
        DispatchQueue.main.async {
            self.isListening = true
            self.delegate?.voiceInputManagerDidStartListening(self)
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        DispatchQueue.main.async {
            self.isListening = false
            self.delegate?.voiceInputManagerDidStopListening(self)
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
    case recognizerNotAvailable
    case requestCreationFailed
    case audioSessionFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized"
        case .recognizerNotAvailable:
            return "Speech recognizer not available"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        case .audioSessionFailed:
            return "Failed to configure audio session"
        }
    }
}
