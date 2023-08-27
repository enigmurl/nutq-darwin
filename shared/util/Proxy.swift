//
//  Proxy.swift
//  nutqdarwin
//
//  Created by Manu Bhat on 8/25/23.
//

import Foundation

fileprivate let auth_buffer: TimeInterval = .minute
fileprivate func url_base() -> String {
#if DEBUG
    return "http://localhost:8000"
#else
    return "https://api.esoteric.manubhat.com"
#endif
}

fileprivate enum RequestError: Error {
    case networkError
    case jsonError
}

fileprivate struct AdminServerClaim: Codable {
    let id: Int
    let username: String
    let token_type: String
    let access: Int
    let exp: Int
}

fileprivate struct RefreshClaim: Codable {
    let id: Int
    let token_type: String
    let exp: Int
}

fileprivate struct AuthResponse: Codable {
    let id: Int
    let username: String
    let access_claim: AdminServerClaim
    let access_token: String
    let refresh_claim: RefreshClaim
    let refresh_token: String
}

fileprivate struct ReauthResponse: Codable {
    let access_claim: AdminServerClaim
    let access_token: String
}

fileprivate func base<T>(token: String?, path: String, body: Data? = nil, method: String = "GET") async -> T?
where T: Decodable
{
    guard let url = URL(string: url_base() + path) else {
        return nil
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = method;
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    if let token = token {
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    }
    
    let result: T? = try? await withCheckedThrowingContinuation { continuation in
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                continuation.resume(throwing: RequestError.networkError)
                return
            }
            
            guard let data = data else {
                continuation.resume(throwing: RequestError.networkError)
                return
            }
            
            guard let json = try? JSONDecoder().decode(T.self, from: data) else {
                continuation.resume(throwing: RequestError.jsonError)
                return
            }
            
            continuation.resume(returning: json)
        }.resume()
    }
    
    return result
}

func sign_in(env: EnvState, username: String, password: String) async -> Bool {
    guard let result: AuthResponse = await base(
        token: nil,
        path: "/auth/authorize",
        body: try! JSONEncoder().encode(["username": username, "password": password]),
        method: "POST"
    ) else {
        return false
    }
  
    DispatchQueue.main.async {
        env.esotericToken = EsotericUser(id: result.id, username: result.username, access: result.access_token, refresh: result.refresh_token, access_exp: result.access_claim.exp, refresh_exp: result.refresh_claim.exp)
    }
    
    return true
}

fileprivate func refresh(env: EnvState) async -> Bool {
    if let exp = env.esotericToken?.refresh_exp, Date.now.timeIntervalSince1970 + auth_buffer < TimeInterval(exp) {
        DispatchQueue.main.async {
            env.esotericToken = nil
        }
        return false
    }
    
    guard let result: ReauthResponse = await base(
        token: env.esotericToken?.refresh,
        path: "/auth/reauthorize",
        body: try! JSONEncoder().encode(["refresh": env.esotericToken!.refresh]),
        method: "POST"
    ) else {
        return false
    }
    
    DispatchQueue.main.async {
        env.esotericToken?.access = result.access_token
        env.esotericToken?.access_exp = result.access_claim.exp
    }
            
    return true
}

func auth_request<T>(env: EnvState, _ path: String, body: Data? = nil, method: String = "GET") async -> T? where T: Decodable {
    if let exp = env.esotericToken?.access_exp, Date.now.timeIntervalSince1970 + auth_buffer < TimeInterval(exp) {
        if !(await refresh(env: env)) {
            return nil
        }
    }
    
    guard let token = env.esotericToken?.access else {
        return nil
    }

    return await base(token: token, path: path, body: body, method: method)
}

func sign_out(env: EnvState) {
    env.esotericToken = nil
}
