//
//  OllamaRequestService.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Dependencies
import DependenciesMacros
import Alamofire
import Sharing
import Foundation

@available(macOS 26.0, *)
@DependencyClient
public struct OllamaRequestService: Sendable {
    public var tags: @Sendable () async throws -> [OllamaTag] = { [] }
    public var chat: @Sendable (_ model: String, _ prompt: String) async throws -> String = { _,_ in "" }
}

@available(macOS 26.0, *)
extension OllamaRequestService: DependencyKey {
    public static var liveValue: OllamaRequestService = {
        @Shared(.ollamaUrl) var ollamaUrl: String
        let baseURLString = ollamaUrl
        return .init {
            guard let url = URL(string: baseURLString + "/api/tags") else {
                return []
            }
            
            return try await withCheckedThrowingContinuation { continuation in
                AF.request(url)
                    .validate()
                    .responseDecodable(of: OllamaModels.self) { response in
                        switch response.result {
                            case .success(let models):
                                continuation.resume(returning: models.models)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                        }
                    }
            }
        } chat: { model, prompt in
            guard let url = URL(string: baseURLString + "/api/generate") else {
                return ""
            }
            
            return try await withCheckedThrowingContinuation { continuation in
                let parameters: Parameters = [
                    "model": model,
                    "prompt": prompt,
                    "stream": false
                ]
                AF.request(
                    url,
                    method: .post,
                    parameters: parameters,
                    encoding: JSONEncoding.default
                )
                    .validate()
                    .responseDecodable(of: OllamaChatMessage.self) { response in
                        switch response.result {
                            case .success(let ollamaChatMessage):
                                continuation.resume(returning: ollamaChatMessage.response)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                        }
                    }
            }
        }
    }()
    
    public static let testValue = Self()
}

@available(macOS 26.0, *)
extension DependencyValues {
    public var ollamaRequestService: OllamaRequestService {
        get { self[OllamaRequestService.self] }
        set { self[OllamaRequestService.self] = newValue }
    }
}
