import Octokit
import Foundation

// MARK: model

public struct Repository {
    public let owner: User
    public let name: String
    public let fullName: String
    public let id: Int
    public let isPrivate: Bool
    public let description: String
    public let isFork: Bool
    public let gitURL: String
    public let sshURL: String
    public let cloneURL: String

    public init(_ json: [String: AnyObject]) {
        owner = User(json["owner"] as! [String: AnyObject])
        name = json["name"] as! String
        fullName = json["full_name"] as! String
        id = json["id"] as! Int
        isPrivate = json["private"] as! Bool
        description = json["description"] as! String
        isFork = json["fork"] as! Bool
        gitURL = json["git_url"] as! String
        sshURL = json["ssh_url"] as! String
        cloneURL = json["clone_url"] as! String
    }
}

// MARK: request

public extension Octokit {
    public func repositories(completion: (response: Response<[Repository]>) -> Void) {
        let request = RepositoryRouter.ReadRepositories(self)
        loadJSON(request.URLRequest, expectedResultType: [[String: AnyObject]].self) { json, error in
            if let error = error {
                completion(response: Response.Failure(error))
            }

            if let json = json {
                let repos = json.map { Repository($0) }
                completion(response: Response.Success(Box(repos)))
            }
        }
    }

    public func repository(owner: String, name: String, completion: (response: Response<Repository>) -> Void) {
        let request = RepositoryRouter.ReadRepository(self, owner, name)
        loadJSON(request.URLRequest, expectedResultType: [String: AnyObject].self) { json, error in
            if let error = error {
                completion(response: Response.Failure(error))
            } else {
                if let json = json {
                    let repo = Repository(json)
                    completion(response: Response.Success(Box(repo)))
                }
            }
        }
    }
}

// MARK: Router

public enum RepositoryRouter {
    case ReadRepositories(Octokit)
    case ReadRepository(Octokit, String, String)

    var method: HTTPMethod {
        return .GET
    }

    var path: String {
        switch self {
        case .ReadRepositories:
            return "/user/repos"
        case .ReadRepository(_, let owner, let name):
            return "/repos/\(owner)/\(name)"
        }
    }

    public var URLRequest: NSURLRequest? {
        switch self {
        case .ReadRepositories(let kit):
            return kit.request(path, method: method)
        case .ReadRepository(let kit, _, _):
            return kit.request(path, method: method)
        }
    }
}