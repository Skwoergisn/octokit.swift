//
//  Git.swift
//  OctoKit
//
//  Created by Antoine van der Lee on 25/01/2022.
//  Copyright © 2020 nerdish by nature. All rights reserved.
//

import Foundation
import RequestKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: request

public extension Octokit {
    /// Deletes a reference.
    /// - Parameters:
    ///   - session: RequestKitURLSession, defaults to URLSession.shared()
    ///   - owner: The user or organization that owns the repositories.
    ///   - repo: The repository on which the reference needs to be deleted.
    ///   - ref: The reference to delete.
    ///   - completion: Callback for the outcome of the deletion.
    @discardableResult
    func deleteReference(_ session: RequestKitURLSession = URLSession.shared,
                         owner: String,
                         repository: String,
                         ref: String,
                         completion: @escaping (_ response: Error?) -> Void) -> URLSessionDataTaskProtocol? {
        let router = GITRouter.deleteReference(configuration, owner, repository, ref)
        return router.load(session, completion: completion)
    }
    
    enum GITError: Swift.Error {
        case refUpdateShaMismatch
    }
    
    #if compiler(>=5.5.2) && canImport(_Concurrency)
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func commit(files: [Blob], to repository: Repository, message: String) async throws {
        
        // Get root tree
        let rootTree = try await rootTree(of: repository)
        
        // Get parent commit
        let parentCommit = try await getParentCommit(of: repository)
        
        // Create blobs
        let blobSHAs: [String: Blob] = try await files.concurrentMap({ blob in
            try await (createBlob(blob, in: repository).sha, blob)
        }).reduce(into: [String: Blob](), { partialResult, tuple in
            partialResult[tuple.0] = tuple.1
        })
        
        // Create tree
        let newTree = try await createTree(blobSHAs: blobSHAs, under: rootTree, in: repository)
        
        // Commit tree
        let commit = try await commit(message: message, tree: newTree, parentCommit: parentCommit, in: repository)
        
        // Update reference
        guard try await updateRef(for: commit, in: repository).object.sha == commit.sha else {
            throw GITError.refUpdateShaMismatch
        }
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func createBlob(_ blob: Blob, in repo: Repository) async throws -> GitResponses.Blob {
        let router = GITRouter.createBlob(configuration, repo: repo, body: .init(content: try blob.content.base64EncodedString(), encoding: blob.content.encoding))
        return try await router.post(URLSession.shared, expectedResultType: GitResponses.Blob.self)
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func rootTree(of repository: Repository) async throws -> GitResponses.Tree {
        let router = GITRouter.rootTree(configuration, repo: repository)
        return try await router.load(expectedResultType: GitResponses.Tree.self)
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func createTree(blobSHAs: [String: Blob], under rootTree: GitResponses.Tree, in repository: Repository) async throws -> GitResponses.Tree {
        let router = GITRouter.createTree(configuration,
                                          repo: repository,
                                          body:
                .init(tree: blobSHAs.map({ key, value in
                        .init(path: value.fileName, sha: key)
                }),
                      baseTreeSHA: rootTree.sha))
        return try await router.post(URLSession.shared, expectedResultType: GitResponses.Tree.self)
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func getParentCommit(of repository: Repository) async throws -> GitResponses.Reference {
        let router = GITRouter.parentCommit(configuration, repo: repository)
        return try await router.load(expectedResultType: GitResponses.Reference.self)
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func commit(message: String, tree: GitResponses.Tree, parentCommit: GitResponses.Reference, in repository: Repository) async throws -> GitResponses.Commit {
        let router = GITRouter.createCommit(configuration,
                                            repo: repository,
                                            body: .init(treeSHA: tree.sha,
                                                        message: message,
                                                        parents: [parentCommit.object.sha]))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(Time.rfc3339DateFormatter)
        return try await router.post(URLSession.shared, decoder: decoder, expectedResultType: GitResponses.Commit.self)
    }
    
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func updateRef(for commit: GitResponses.Commit, in repository: Repository) async throws -> GitResponses.Reference {
        let router = GITRouter.updateRef(configuration,
                                         repo: repository,
                                         body: .init(sha: commit.sha))
        return try await router.post(URLSession.shared, expectedResultType: GitResponses.Reference.self)
    }
    #endif
}

public extension Octokit {
    enum GitRequestBodies {
        public struct Blob {
            let content: String
            let encoding: String
            
            var parameters: [String: Any] {
                [
                    "content": content,
                    "encoding": encoding
                ]
            }
        }
        
        public struct Tree {
            let tree: [Object]
            let baseTreeSHA: String
            
            struct Object {
                let path: String
                let mode: String = "100644"
                let type: String = "blob"
                let sha: String
                
                var parameters: [String: Any] {
                    [
                        "path": path,
                        "mode": mode,
                        "type": type,
                        "sha": sha
                    ]
                }
            }
            
            enum CodingKeys: String, CodingKey {
                case tree = "tree"
                case baseTreeSHA = "base_tree"
            }
            
            var parameters: [String: Any] {
                [
                    "base_tree": baseTreeSHA,
                    "tree": tree.map(\.parameters)
                ]
            }
        }
        
        public struct Commit: Codable {
            let treeSHA: String
            let message: String
            let parents: [String]
            
            var parameters: [String: Any] {
                [
                    "tree": treeSHA,
                    "message": message,
                    "parents": parents
                ]
            }
        }
        
        public struct Ref {
            let sha: String
            
            var parameters: [String: Any] {
                ["sha": sha]
            }
        }
    }
    
    enum GitResponses {
        /// The hierarchy between files in a Git repository.
        // MARK: - Tree
        public struct Tree: Codable {
            let sha: String
            /// Objects specifying a tree structure
            let tree: [Object]
            let truncated: Bool
            let url: String
            
            // MARK: - Tree
            public  struct Object: Codable {
                let mode, path, sha: String?
                let size: Int?
                let type, url: String?
            }
        }
        
        public struct Blob: Codable {
            let sha: String
            let url: URL
        }
        
        /// Git references within a repository
        // MARK: - Reference
        public struct Reference: Codable {
            let nodeID: String
            let object: Object
            let ref, url: String

            enum CodingKeys: String, CodingKey {
                case nodeID = "node_id"
                case object, ref, url
            }
            
            // MARK: - Object
            public struct Object: Codable {
                /// SHA for the reference
                let sha: String
                let type, url: String
            }
        }
        
        /// Low-level Git commit operations within a repository
        // MARK: - Commit
        public struct Commit: Codable {
            /// Identifying information for the git-user
            let author: Author
            /// Identifying information for the git-user
            let committer: Committer
            let htmlURL: String
            /// Message describing the purpose of the commit
            let message: String
            let nodeID: String
            let parents: [Parent]
            /// SHA for the commit
            let sha: String
            let tree: Tree
            let url: String
            let verification: Verification

            enum CodingKeys: String, CodingKey {
                case author, committer
                case htmlURL = "html_url"
                case message
                case nodeID = "node_id"
                case parents, sha, tree, url, verification
            }
            
            /// Identifying information for the git-user
            // MARK: - Author
            struct Author: Codable {
                /// Timestamp of the commit
                let date: Date
                /// Git email address of the user
                let email: String
                /// Name of the git user
                let name: String
            }

            /// Identifying information for the git-user
            // MARK: - Committer
            struct Committer: Codable {
                /// Timestamp of the commit
                let date: Date
                /// Git email address of the user
                let email: String
                /// Name of the git user
                let name: String
            }

            // MARK: - Parent
            struct Parent: Codable {
                let htmlURL: String
                /// SHA for the commit
                let sha: String
                let url: String

                enum CodingKeys: String, CodingKey {
                    case htmlURL = "html_url"
                    case sha, url
                }
            }

            // MARK: - Tree
            struct Tree: Codable {
                /// SHA for the commit
                let sha: String
                let url: String
            }

            // MARK: - Verification
            struct Verification: Codable {
                let payload: String?
                let reason: String
                let signature: String?
                let verified: Bool
            }
        }
    }
}

public struct Blob {
    var fileName: String
    var content: Octokit.BlobType
    
    public init(fileName: String, content: Octokit.BlobType) {
        self.fileName = fileName
        self.content = content
    }
    
    public init(fileName: String, content: String) {
        self.fileName = fileName
        self.content = .string(content)
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
extension Sequence {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            try await values.append(transform(element))
        }

        return values
    }
    
    func concurrentMap<T>(
            _ transform: @escaping (Element) async throws -> T
        ) async throws -> [T] {
            let tasks = map { element in
                Task {
        try await transform(element)
    }
            }

            return try await tasks.asyncMap { task in
                try await task.value
            }
        }
}

public extension Octokit {
    enum BlobType {
        case data(Data)
        case string(String)
        
        func base64EncodedString() throws -> String {
            switch self {
            case let .data(data):
                return data.base64EncodedString()
            case let .string(string):
                guard let data = string.data(using: .utf8) else {
                    throw Error.invalidString
                }
                return data.base64EncodedString()
            }
        }
        
        var encoding: String {
            switch self {
            case .data: return "base64"
            case .string: return "utf_8"
            }
        }
        
        enum Error: Swift.Error {
            case invalidString
        }
    }
}

// MARK: Router

enum GITRouter: JSONPostRouter {
    case deleteReference(Configuration, String, String, String)
    
    case rootTree(Configuration, repo: Repository)
    case createBlob(Configuration, repo: Repository, body: Octokit.GitRequestBodies.Blob)
    case createTree(Configuration, repo: Repository, body: Octokit.GitRequestBodies.Tree)
    case parentCommit(Configuration, repo: Repository)
    case createCommit(Configuration, repo: Repository, body: Octokit.GitRequestBodies.Commit)
    case updateRef(Configuration, repo: Repository, body: Octokit.GitRequestBodies.Ref)

    var configuration: Configuration {
        switch self {
        case let .deleteReference(config, _, _, _),
            let .rootTree(config, _),
            let .createBlob(config, _, _),
            let .createTree(config, _, _),
            let .parentCommit(config, _),
            let .createCommit(config, _, _),
            let .updateRef(config, _, _)
            : return config
        }
    }

    var method: HTTPMethod {
        switch self {
        case .deleteReference:
            return .DELETE
            
        case .rootTree,
                .parentCommit:
            return .GET
            
        case .createTree,
                .createBlob,
                .createCommit:
            return .POST
            
        case .updateRef:
            return .PATCH
        }
    }

    var encoding: HTTPEncoding {
        switch self {
        case .deleteReference:
            return .url
            
        default:
            return .json
        }
    }

    var params: [String: Any] {
        switch self {
        case .deleteReference, .rootTree, .parentCommit:
            return [:]
            
        case let .createBlob(_, _, body): return body.parameters
        case let .createTree(_, _, body): return body.parameters
        case let .createCommit(_, _, body): return body.parameters
        case let .updateRef(_, _, body): return body.parameters
        }
    }

    var path: String {
        switch self {
        case let .deleteReference(_, owner, repo, reference):
            return "repos/\(owner)/\(repo)/git/refs/\(reference)"
            
        case let .rootTree(_, repo):
            return "repos/\(repo.owner.login!)/\(repo.name!)/git/trees/main"
            
        case let .createBlob(_, repo, _):
            return "/repos/\(repo.owner.login!)/\(repo.name!)/git/blobs"
            
        case let .createTree(_, repo, _):
            return "/repos/\(repo.owner.login!)/\(repo.name!)/git/trees"
            
        case let .createCommit(_, repo, _):
            return "/repos/\(repo.owner.login!)/\(repo.name!)/git/commits"
            
        case let .updateRef(_, repo, _),
            let .parentCommit(_, repo):
            return "/repos/\(repo.owner.login!)/\(repo.name!)/git/refs/heads/main"
        }
    }
}
