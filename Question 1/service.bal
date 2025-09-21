import ballerina/http;
import ballerina/io;
import ballerina/time;
import ballerina/file;

// Here are the data Types
public enum AssetStatus {
    ACTIVE = "ACTIVE",
    UNDER_REPAIR = "UNDER_REPAIR",
    DISPOSED = "DISPOSED"
}

public enum WorkOrderStatus {
    OPEN = "OPEN",
    IN_PROGRESS = "IN_PROGRESS",
    CLOSED = "CLOSED"
}

public enum UserRole {
    SERVICE_ADMIN = "SERVICE_ADMIN",
    CLIENT_USER = "CLIENT_USER"
}

public type Component record {
    string componentId;
    string name;
    string description;
    string status;
};

public type MaintenanceSchedule record {
    string scheduleId;
    string description;
    string frequency;
    time:Civil nextDueDate;
    boolean isOverdue;
};

public type Task record {
    string taskId;
    string description;
    string status;
    string assignedTo?;
};

public type WorkOrder record {
    string workOrderId;
    string description;
    WorkOrderStatus status;
    time:Civil dateCreated;
    time:Civil dateCompleted?;
    map<Task> tasks;
};

public type Asset record {
    string assetTag;
    string name;
    string faculty;
    string department;
    AssetStatus status;
    time:Civil acquiredDate;
    map<Component> components;
    map<MaintenanceSchedule> schedules;
    map<WorkOrder> workOrders;
};

public type User record {
    string username;
    string password;
    UserRole role;
    string faculty?;
};

public type LoginRequest record {
    string username;
    string password;
};

public type LoginResponse record {
    string token;
    UserRole role;
    string message;
};

public type CreateUserRequest record {
    string username;
    string password;
    UserRole role;
    string faculty?;
};

public type SearchRequest record {
    string query;
    string searchType; // The options are: "name", "faculty", "department", "assetTag", "all"
};

// Here is where the in-memory storage is loaded from and saved to JSON
map<Asset> assetsDatabase = {};
map<User> usersDatabase = {};
map<string> activeSessions = {};

// Here are the file paths to the database files in JSON format
const string ASSETS_FILE = "data/assets.json";
const string USERS_FILE = "data/users.json";

function loadAssetsFromFile() returns error? {
    if !check file:test(ASSETS_FILE, file:EXISTS) {
        io:println("Assets file not found, creating with sample data");
        check initializeSampleAssets();
        return;
    }
    
    string content = check io:fileReadString(ASSETS_FILE);
    json assetsJson = check content.fromJsonString();
    
    if assetsJson is map<json> {
        foreach [string, json] [tag, assetJson] in assetsJson.entries() {
            Asset? asset = parseAssetFromJson(assetJson);
            if asset is Asset {
                assetsDatabase[tag] = asset;
            }
        }
    }
    io:println("Loaded " + assetsDatabase.length().toString() + " assets from file");
}

function saveAssetsToFile() returns error? {
    if !check file:test("data", file:EXISTS) {
        check file:createDir("data");
    }
    
    map<json> assetsJson = {};
    foreach [string, Asset] [tag, asset] in assetsDatabase.entries() {
        assetsJson[tag] = convertAssetToJson(asset);
    }
    
    string jsonString = assetsJson.toJsonString();
    check io:fileWriteString(ASSETS_FILE, jsonString);
}

function loadUsersFromFile() returns error? {
    if !check file:test(USERS_FILE, file:EXISTS) {
        io:println("Users file not found, creating with default users");
        check initializeDefaultUsers();
        return;
    }
    
    string content = check io:fileReadString(USERS_FILE);
    json usersJson = check content.fromJsonString();
    
    if usersJson is map<json> {
        foreach [string, json] [username, userJson] in usersJson.entries() {
            User? user = parseUserFromJson(userJson);
            if user is User {
                usersDatabase[username] = user;
            }
        }
    }
    io:println("Loaded " + usersDatabase.length().toString() + " users from file");
}

function saveUsersToFile() returns error? {
    if !check file:test("data", file:EXISTS) {
        check file:createDir("data");
    }
    
    map<json> usersJson = {};
    foreach [string, User] [username, user] in usersDatabase.entries() {
        usersJson[username] = {
            "username": user.username,
            "password": user.password,
            "role": user.role.toString(),
            "faculty": user.faculty ?: ""
        };
    }
    
    string jsonString = usersJson.toJsonString();
    check io:fileWriteString(USERS_FILE, jsonString);
}

// JSON parsing functions are here (CRUD)
function parseAssetFromJson(json assetJson) returns Asset? {
    if assetJson is map<json> {
        string? assetTag = assetJson["assetTag"].toString();
        string? name = assetJson["name"].toString();
        string? faculty = assetJson["faculty"].toString();
        string? department = assetJson["department"].toString();
        string? statusStr = assetJson["status"].toString();
        string? acquiredDateStr = assetJson["acquiredDate"].toString();
        
        if assetTag is string && name is string && faculty is string && 
           department is string && statusStr is string && acquiredDateStr is string {
            
            AssetStatus status = statusStr == "UNDER_REPAIR" ? UNDER_REPAIR : 
                               statusStr == "DISPOSED" ? DISPOSED : ACTIVE;
            
            time:Civil acquiredDate = parseDate(acquiredDateStr);
            
            map<Component> components = {};
            map<MaintenanceSchedule> schedules = {};
            map<WorkOrder> workOrders = {};
            
            return {
                assetTag: assetTag,
                name: name,
                faculty: faculty,
                department: department,
                status: status,
                acquiredDate: acquiredDate,
                components: components,
                schedules: schedules,
                workOrders: workOrders
            };
        }
    }
    return ();
}

function parseUserFromJson(json userJson) returns User? {
    if userJson is map<json> {
        string? username = userJson["username"].toString();
        string? password = userJson["password"].toString();
        string? roleStr = userJson["role"].toString();
        string? faculty = userJson["faculty"].toString();
        
        if username is string && password is string && roleStr is string {
            UserRole role = roleStr == "SERVICE_ADMIN" ? SERVICE_ADMIN : CLIENT_USER;
            
            return {
                username: username,
                password: password,
                role: role,
                faculty: faculty == "" ? () : faculty
            };
        }
    }
    return ();
}

function convertAssetToJson(Asset asset) returns json {
    return {
        "assetTag": asset.assetTag,
        "name": asset.name,
        "faculty": asset.faculty,
        "department": asset.department,
        "status": asset.status.toString(),
        "acquiredDate": formatDate(asset.acquiredDate),
        "components": {},
        "schedules": {},
        "workOrders": {}
    };
}

function parseDate(string dateStr) returns time:Civil {
    string[] parts = re `-`.split(dateStr);
    if parts.length() == 3 {
        int|error year = int:fromString(parts[0]);
        int|error month = int:fromString(parts[1]);
        int|error day = int:fromString(parts[2]);
        
        if year is int && month is int && day is int {
            return {year: year, month: month, day: day, hour: 0, minute: 0, second: 0};
        }
    }
    return {year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0};
}

function formatDate(time:Civil date) returns string {
    return date.year.toString() + "-" + 
           string:padStart(date.month.toString(), 2, "0") + "-" + 
           string:padStart(date.day.toString(), 2, "0");
}

// Set up sample data for first time lauch to help any one on start up the application and be able to view, search etc
function initializeSampleAssets() returns error? {
    time:Civil sampleDate = {year: 2026, month: 3, day: 10, hour: 0, minute: 0, second: 0};
    time:Civil dueDateOverdue = {year: 2026, month: 8, day: 15, hour: 0, minute: 0, second: 0};
    time:Civil dueDateFuture = {year: 2026, month: 1, day: 15, hour: 0, minute: 0, second: 0};
    
    Asset sampleAsset = {
        assetTag: "EQ-001",
        name: "3D Printer",
        faculty: "Computing & Informatics",
        department: "Software Engineering",
        status: ACTIVE,
        acquiredDate: sampleDate,
        components: {
            "comp1": {
                componentId: "comp1",
                name: "Print Head",
                description: "Main printing component",
                status: "ACTIVE"
            }
        },
        schedules: {
            "sched1": {
                scheduleId: "sched1",
                description: "Quarterly Maintenance",
                frequency: "QUARTERLY",
                nextDueDate: dueDateOverdue,
                isOverdue: true
            }
        },
        workOrders: {}
    };
    
    Asset sampleAsset2 = {
        assetTag: "EQ-002",
        name: "Lab Server",
        faculty: "Computing & Informatics",
        department: "Computer Science",
        status: ACTIVE,
        acquiredDate: sampleDate,
        components: {},
        schedules: {
            "sched2": {
                scheduleId: "sched2",
                description: "Annual Service",
                frequency: "YEARLY",
                nextDueDate: dueDateFuture,
                isOverdue: false
            }
        },
        workOrders: {}
    };
    
    assetsDatabase["EQ-001"] = sampleAsset;
    assetsDatabase["EQ-002"] = sampleAsset2;
    
    check saveAssetsToFile();
    io:println("Sample assets initialized and saved to file");
}

function initializeDefaultUsers() returns error? {
    usersDatabase["admin"] = {
        username: "admin",
        password: "admin123",
        role: SERVICE_ADMIN
    };
    
    usersDatabase["client1"] = {
        username: "client1",
        password: "client123",
        role: CLIENT_USER,
        faculty: "Computing & Informatics"
    };
    
    usersDatabase["client2"] = {
        username: "client2",
        password: "client123",
        role: CLIENT_USER,
        faculty: "Engineering"
    };
    
    check saveUsersToFile();
    io:println("Default users initialized and saved to file");
}

// Utility (which is a collection of reusable helper functions or classes that perform common, independent tasks) functions
function generateToken() returns string {
    time:Utc currentTime = time:utcNow();
    return "token_" + currentTime[0].toString();
}

function checkOverdueSchedules() {
    foreach Asset asset in assetsDatabase {
        foreach MaintenanceSchedule schedule in asset.schedules {
            time:Utc currentTime = time:utcNow();
            time:Civil|error scheduleTime = time:utcToCivil(currentTime);
            if scheduleTime is time:Civil {
                schedule.isOverdue = schedule.nextDueDate.year < scheduleTime.year ||
                                   (schedule.nextDueDate.year == scheduleTime.year && 
                                    schedule.nextDueDate.month < scheduleTime.month);
            }
        }
    }
}

function searchAssets(string query, string searchType) returns Asset[] {
    Asset[] results = [];
    string lowerQuery = query.toLowerAscii();
    
    foreach Asset asset in assetsDatabase {
        boolean matches = false;
        
        match searchType {
            "name" => {
                matches = asset.name.toLowerAscii().includes(lowerQuery);
            }
            "faculty" => {
                matches = asset.faculty.toLowerAscii().includes(lowerQuery);
            }
            "department" => {
                matches = asset.department.toLowerAscii().includes(lowerQuery);
            }
            "assetTag" => {
                matches = asset.assetTag.toLowerAscii().includes(lowerQuery);
            }
            "all" => {
                matches = asset.name.toLowerAscii().includes(lowerQuery) ||
                         asset.faculty.toLowerAscii().includes(lowerQuery) ||
                         asset.department.toLowerAscii().includes(lowerQuery) ||
                         asset.assetTag.toLowerAscii().includes(lowerQuery);
            }
        }
        
        if matches {
            results.push(asset);
        }
    }
    
    return results;
}

// Authentication middleware (This is the intermediary layer between the different components (client, server and JSON files))
function authenticate(http:Request req, UserRole requiredRole) returns string|error {
    string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
    if authHeader is http:HeaderNotFoundError {
        return error("Authorization header missing");
    }
    
    string token = authHeader;
    string? username = activeSessions[token];
    if username is () {
        return error("Invalid token");
    }
    
    User? user = usersDatabase[username];
    if user is () {
        return error("User not found");
    }
    
    if user.role != SERVICE_ADMIN && user.role != requiredRole {
        return error("Insufficient permissions");
    }
    
    return username;
}

// Data is loaded/imported when the service starts
function init() {
    error? loadUsersResult = loadUsersFromFile();
    if loadUsersResult is error {
        io:println("Error loading users: " + loadUsersResult.message());
    }
    
    error? loadAssetsResult = loadAssetsFromFile();
    if loadAssetsResult is error {
        io:println("Error loading assets: " + loadAssetsResult.message());
    }
    
    io:println("NUST Asset Management Service initialized successfully!");
    io:println("Service is running on http://localhost:8080");
    io:println("Data is persisted to JSON files in ./data/ directory");
    io:println("Here are the Available endpoints:");
    io:println("- GET  /api/health");
    io:println("- POST /api/auth/login");
    io:println("- POST /api/users (admin only)");
    io:println("- GET  /api/assets");
    io:println("- POST /api/assets/search");
    io:println("- GET  /api/assets/faculty/{faculty}");
    io:println("- GET  /api/assets/overdue");
}

// REST API Service is set starting here for health check, authentication, user management, asset management, component management, schedule management and work order management
service /api on new http:Listener(8080) {
    
    resource function get health() returns json {
        return {
            "status": "Service is running", 
            "timestamp": time:utcNow()[0],
            "users_count": usersDatabase.length(),
            "assets_count": assetsDatabase.length(),
            "data_persisted": true
        };
    }
    

    resource function post auth/login(LoginRequest loginReq) returns LoginResponse|http:BadRequest {
        io:println("Login attempt for: " + loginReq.username);
        
        User? user = usersDatabase[loginReq.username];
        if user is () {
            io:println("User not found: " + loginReq.username);
            return http:BAD_REQUEST;
        }
        
        if user.password != loginReq.password {
            io:println("Invalid password for user: " + loginReq.username);
            return http:BAD_REQUEST;
        }
        
        string token = generateToken();
        activeSessions[token] = loginReq.username;
        
        io:println("Login successful for: " + loginReq.username);
        
        return {
            token: token,
            role: user.role,
            message: "Login successful"
        };
    }
    
    resource function post auth/logout(http:Request req) returns json {
        string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
        if authHeader is string {
            _ = activeSessions.remove(authHeader);
            io:println("User logged out");
        }
        return {"message": "Logged out successfully"};
    }
    
    resource function post users(http:Request req, CreateUserRequest userReq) returns json|http:BadRequest|http:Unauthorized {
        string|error username = authenticate(req, SERVICE_ADMIN);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        if usersDatabase.hasKey(userReq.username) {
            return http:BAD_REQUEST;
        }
        
        User newUser = {
            username: userReq.username,
            password: userReq.password,
            role: userReq.role,
            faculty: userReq.faculty
        };
        
        usersDatabase[userReq.username] = newUser;
        
        error? saveResult = saveUsersToFile();
        if saveResult is error {
            io:println("Error saving users: " + saveResult.message());
        }
        
        io:println("User " + userReq.username + " created by: " + username);
        return {"message": "User created successfully", "username": userReq.username};
    }
    
    resource function get assets(http:Request req) returns Asset[]|http:Unauthorized|http:InternalServerError {
        string|error username = authenticate(req, CLIENT_USER);
        if username is error {
            io:println("Unauthorized access to assets");
            return http:UNAUTHORIZED;
        }
        
        checkOverdueSchedules();
        io:println("Assets requested by: " + username);
        return assetsDatabase.toArray();
    }
    
    resource function post assets/search(http:Request req, SearchRequest searchReq) returns Asset[]|http:Unauthorized {
        string|error username = authenticate(req, CLIENT_USER);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        Asset[] results = searchAssets(searchReq.query, searchReq.searchType);
        io:println("Search for '" + searchReq.query + "' by " + username + " returned " + results.length().toString() + " results");
        return results;
    }
    
    resource function get assets/[string assetTag](http:Request req) returns Asset|http:NotFound|http:Unauthorized {
        string|error username = authenticate(req, CLIENT_USER);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        Asset? asset = assetsDatabase[assetTag];
        if asset is () {
            return http:NOT_FOUND;
        }
        
        io:println("Asset " + assetTag + " requested by: " + username);
        return asset;
    }
    
    resource function post assets(http:Request req, Asset newAsset) returns Asset|http:BadRequest|http:Unauthorized {
        string|error username = authenticate(req, SERVICE_ADMIN);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        if assetsDatabase.hasKey(newAsset.assetTag) {
            return http:BAD_REQUEST;
        }
        
        assetsDatabase[newAsset.assetTag] = newAsset;
        
        error? saveResult = saveAssetsToFile();
        if saveResult is error {
            io:println("Error saving assets: " + saveResult.message());
        }
        
        io:println("Asset " + newAsset.assetTag + " created by: " + username);
        return newAsset;
    }
    
    resource function put assets/[string assetTag](http:Request req, Asset updatedAsset) returns Asset|http:NotFound|http:Unauthorized {
        string|error username = authenticate(req, SERVICE_ADMIN);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        if !assetsDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        
        updatedAsset.assetTag = assetTag;
        assetsDatabase[assetTag] = updatedAsset;
        
        error? saveResult = saveAssetsToFile();
        if saveResult is error {
            io:println("Error saving assets: " + saveResult.message());
        }
        
        io:println("Asset " + assetTag + " updated by: " + username);
        return updatedAsset;
    }
    
    resource function delete assets/[string assetTag](http:Request req) returns json|http:NotFound|http:Unauthorized {
        string|error username = authenticate(req, SERVICE_ADMIN);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        if !assetsDatabase.hasKey(assetTag) {
            return http:NOT_FOUND;
        }
        
        _ = assetsDatabase.remove(assetTag);
        
        error? saveResult = saveAssetsToFile();
        if saveResult is error {
            io:println("Error saving assets: " + saveResult.message());
        }
        
        io:println("Asset " + assetTag + " deleted by: " + username);
        return {"message": "Asset deleted successfully"};
    }
    
    resource function get assets/faculty/[string faculty](http:Request req) returns Asset[]|http:Unauthorized {
        string|error username = authenticate(req, CLIENT_USER);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        Asset[] facultyAssets = [];
        foreach Asset asset in assetsDatabase {
            if asset.faculty == faculty {
                facultyAssets.push(asset);
            }
        }
        
        io:println("Faculty assets (" + faculty + ") requested by: " + username);
        return facultyAssets;
    }
    
    resource function get assets/overdue(http:Request req) returns Asset[]|http:Unauthorized {
        string|error username = authenticate(req, CLIENT_USER);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        checkOverdueSchedules();
        Asset[] overdueAssets = [];
        
        foreach Asset asset in assetsDatabase {
            boolean hasOverdue = false;
            foreach MaintenanceSchedule schedule in asset.schedules {
                if schedule.isOverdue {
                    hasOverdue = true;
                    break;
                }
            }
            if hasOverdue {
                overdueAssets.push(asset);
            }
        }
        
        io:println("Overdue assets requested by: " + username);
        return overdueAssets;
    }
    
    resource function post assets/[string assetTag]/components(http:Request req, Component component) returns Component|http:NotFound|http:Unauthorized {
        string|error username = authenticate(req, SERVICE_ADMIN);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        Asset? asset = assetsDatabase[assetTag];
        if asset is () {
            return http:NOT_FOUND;
        }
        
        asset.components[component.componentId] = component;
        
        error? saveResult = saveAssetsToFile();
        if saveResult is error {
            io:println("Error saving assets: " + saveResult.message());
        }
        
        io:println("Component " + component.componentId + " added to " + assetTag + " by: " + username);
        return component;
    }
    
    resource function delete assets/[string assetTag]/components/[string componentId](http:Request req) returns json|http:NotFound|http:Unauthorized {
        string|error username = authenticate(req, SERVICE_ADMIN);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        Asset? asset = assetsDatabase[assetTag];
        if asset is () {
            return http:NOT_FOUND;
        }
        
        _ = asset.components.remove(componentId);
        
        error? saveResult = saveAssetsToFile();
        if saveResult is error {
            io:println("Error saving assets: " + saveResult.message());
        }
        
        io:println("Component " + componentId + " removed from " + assetTag + " by: " + username);
        return {"message": "Component deleted successfully"};
    }
    
    resource function post assets/[string assetTag]/schedules(http:Request req, MaintenanceSchedule schedule) returns MaintenanceSchedule|http:NotFound|http:Unauthorized {
        string|error username = authenticate(req, SERVICE_ADMIN);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        Asset? asset = assetsDatabase[assetTag];
        if asset is () {
            return http:NOT_FOUND;
        }
        
        asset.schedules[schedule.scheduleId] = schedule;
        
        error? saveResult = saveAssetsToFile();
        if saveResult is error {
            io:println("Error saving assets: " + saveResult.message());
        }
        
        io:println("Schedule " + schedule.scheduleId + " added to " + assetTag + " by: " + username);
        return schedule;
    }
    
    resource function delete assets/[string assetTag]/schedules/[string scheduleId](http:Request req) returns json|http:NotFound|http:Unauthorized {
        string|error username = authenticate(req, SERVICE_ADMIN);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        Asset? asset = assetsDatabase[assetTag];
        if asset is () {
            return http:NOT_FOUND;
        }
        
        _ = asset.schedules.remove(scheduleId);
        
        error? saveResult = saveAssetsToFile();
        if saveResult is error {
            io:println("Error saving assets: " + saveResult.message());
        }
        
        io:println("Schedule " + scheduleId + " removed from " + assetTag + " by: " + username);
        return {"message": "Schedule deleted successfully"};
    }
    
    resource function post assets/[string assetTag]/workorders(http:Request req, WorkOrder workOrder) returns WorkOrder|http:NotFound|http:Unauthorized {
        string|error username = authenticate(req, SERVICE_ADMIN);
        if username is error {
            return http:UNAUTHORIZED;
        }
        
        Asset? asset = assetsDatabase[assetTag];
        if asset is () {
            return http:NOT_FOUND;
        }
        
        asset.workOrders[workOrder.workOrderId] = workOrder;
        
        error? saveResult = saveAssetsToFile();
        if saveResult is error {
            io:println("Error saving assets: " + saveResult.message());
        }
        
        io:println("Work order " + workOrder.workOrderId + " added to " + assetTag + " by: " + username);
        return workOrder;
    }
}