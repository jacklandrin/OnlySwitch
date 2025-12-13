//
//  OllamaRequestService.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Alamofire
import Sharing
import Foundation

@available(macOS 26.0, *)
final class OllamaLive: Sendable {
    @Sendable
    func models() async throws -> [ProviderModel] {
        @Shared(.ollamaUrl) var ollamaUrl: String
        guard let url = URL(string: ollamaUrl + "/api/tags") else {
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
        .map {
            .init(model: $0.model, id: $0.id)
        }
    }
    
    @Sendable
    func chat(_ model: String, _ prompt: String) async throws -> String {
        @Shared(.ollamaUrl) var ollamaUrl: String
        guard let url = URL(string: ollamaUrl + "/api/generate") else {
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
}
