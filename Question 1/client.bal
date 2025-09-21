import ballerina/http;
import ballerina/io;
import ballerina/time;

// Data Types which are needed for a client
public enum AssetStatus {
    ACTIVE = "ACTIVE",
    UNDER_REPAIR = "UNDER_REPAIR",
    DISPOSED = "DISPOSED"
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

public type Asset record {
    string assetTag;
    string name;
    string faculty;
    string department;
    AssetStatus status;
    time:Civil acquiredDate;
    map<Component> components;
    map<MaintenanceSchedule> schedules;
    map<json> workOrders; // Simplified for client
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
    string searchType;
};

// Command Line Interface for the Asset Management Service
// This client interacts with the service running on localhost:8080
// It provides a menu-driven interface for users to perform various operations
// based on their roles (SERVICE_ADMIN or CLIENT_USER).
public function main() returns error? {
    io:println("=== NUST Asset Management CLI Client ===");
    io:println("Connecting to service at http://localhost:8080...");
    
    http:Client httpClient = check new ("http://localhost:8080");
    

    json|error healthCheck = httpClient->get("/api/health");
    if healthCheck is error {
        io:println("Cannot connect to service. Please ensure the service is running on port 8080.");
        io:println("Start the service first with: bal run service.bal");
        return;
    } else {
        io:println("Connected to service successfully!");
        io:println("Service status: " + healthCheck.toString());
    }
    
    string? currentToken = ();
    UserRole? currentRole = ();
    
    while true {
        if currentToken is () {
            io:println("\n--- Authentication Required!!! ---");
            io:println("Please Enter your Username and Password:");
            
            string username = io:readln("Enter username: ").trim();
            if username == "" {
                io:println("Username cannot be empty. Please try again.");
                continue;
            }
            string password = io:readln("Enter password: ").trim();
            
            LoginRequest loginReq = {username, password};
            
            LoginResponse|error loginResp = httpClient->post("/api/auth/login", loginReq);
            
            if loginResp is LoginResponse {
                currentToken = loginResp.token;
                currentRole = loginResp.role;
                io:println("Login successful!");
                io:println("Role: " + loginResp.role.toString());
                io:println("Token: " + loginResp.token);
            } else {
                io:println("Login failed. Please check your credentials and try again.");
                continue;
            }
        }
        
        io:println("\n--- Main Menu ---");
        io:println("1. View all assets");
        io:println("2. View assets by faculty");
        io:println("3. Check overdue maintenance");
        io:println("4. View specific asset");
        io:println("5. Search assets");
        
        if currentRole == SERVICE_ADMIN {
            io:println("6. Add new asset");
            io:println("7. Update asset");
            io:println("8. Delete asset");
            io:println("9. Add component to asset");
            io:println("10. Add maintenance schedule");
            io:println("11. Create new user");
        }
        
        io:println("0. Logout");
        
        string choice = io:readln("Enter your choice: ").trim();
        
        match choice {
            "1" => {
                check viewAllAssets(httpClient, currentToken);
            }
            "2" => {
                check viewAssetsByFaculty(httpClient, currentToken);
            }
            "3" => {
                check checkOverdueAssets(httpClient, currentToken);
            }
            "4" => {
                check viewSpecificAsset(httpClient, currentToken);
            }
            "5" => {
                check searchAssets(httpClient, currentToken);
            }
            "6" => {
                if currentRole == SERVICE_ADMIN {
                    check addNewAsset(httpClient, currentToken);
                } else {
                    io:println("Access denied. Admin privileges required.");
                }
            }
            "7" => {
                if currentRole == SERVICE_ADMIN {
                    check updateAsset(httpClient, currentToken);
                } else {
                    io:println("Access denied. Admin privileges required.");
                }
            }
            "8" => {
                if currentRole == SERVICE_ADMIN {
                    check deleteAsset(httpClient, currentToken);
                } else {
                    io:println("Access denied. Admin privileges required.");
                }
            }
            "9" => {
                if currentRole == SERVICE_ADMIN {
                    check addComponent(httpClient, currentToken);
                } else {
                    io:println("Access denied. Admin privileges required.");
                }
            }
            "10" => {
                if currentRole == SERVICE_ADMIN {
                    check addMaintenanceSchedule(httpClient, currentToken);
                } else {
                    io:println("Access denied. Admin privileges required.");
                }
            }
            "11" => {
                if currentRole == SERVICE_ADMIN {
                    check createNewUser(httpClient, currentToken);
                } else {
                    io:println("Access denied. Admin privileges required.");
                }
            }
            "0" => {
                string tokenToUse = "";
                if currentToken is string {
                    tokenToUse = currentToken;
                }
                map<string> headers = {"Authorization": tokenToUse};
                json|error logoutResp = httpClient->post("/api/auth/logout", {}, headers);
                if logoutResp is error {
                    io:println("Note: Logout request failed, but session cleared locally.");
                }
                currentToken = ();
                currentRole = ();
                io:println("Logged out successfully");
            }
            _ => {
                io:println("Invalid choice. Please try again.");
            }
        }
    }
}

// Here are the client helper functions (supplementary functions to assist a the main functions):
function viewAllAssets(http:Client httpClient, string? token) returns error? {
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    Asset[]|error response = httpClient->get("/api/assets", headers);
    
    if response is Asset[] {
        io:println("\n=== All Assets ===");
        if response.length() == 0 {
            io:println("No assets found.");
        } else {
            foreach Asset asset in response {
                printAssetSummary(asset);
            }
        }
    } else {
        io:println("Error fetching assets: " + response.message());
    }
}

function searchAssets(http:Client httpClient, string? token) returns error? {
    io:println("\n=== Search Assets ===");
    io:println("Search types:");
    io:println("1. Asset Tag");
    io:println("2. Name");
    io:println("3. Faculty");
    io:println("4. Department");
    io:println("5. All fields");
    
    string searchChoice = io:readln("Choose search type (1-5): ").trim();
    string searchType = "all";
    
    match searchChoice {
        "1" => { searchType = "assetTag"; }
        "2" => { searchType = "name"; }
        "3" => { searchType = "faculty"; }
        "4" => { searchType = "department"; }
        "5" => { searchType = "all"; }
        _ => { searchType = "all"; }
    }
    
    string query = io:readln("Enter search query: ").trim();
    if query == "" {
        io:println("Search query cannot be empty.");
        return;
    }
    
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    
    SearchRequest searchReq = {
        query: query,
        searchType: searchType
    };
    
    Asset[]|error response = httpClient->post("/api/assets/search", searchReq, headers);
    
    if response is Asset[] {
        io:println("\n=== Search Results ===");
        io:println("Found " + response.length().toString() + " assets matching '" + query + "'");
        if response.length() == 0 {
            io:println("No assets found matching your search criteria.");
        } else {
            foreach Asset asset in response {
                printAssetSummary(asset);
            }
        }
    } else {
        io:println("Error searching assets: " + response.message());
    }
}

function createNewUser(http:Client httpClient, string? token) returns error? {
    io:println("\n=== Create New User ===");
    string username = io:readln("Username: ").trim();
    string password = io:readln("Password: ").trim();
    
    io:println("User roles:");
    io:println("1. SERVICE_ADMIN (full access)");
    io:println("2. CLIENT_USER (read-only)");
    
    string roleChoice = io:readln("Choose role (1-2): ").trim();
    UserRole role = roleChoice == "1" ? SERVICE_ADMIN : CLIENT_USER;
    
    string faculty = "";
    if role == CLIENT_USER {
        faculty = io:readln("Faculty (optional): ").trim();
    }
    
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    
    CreateUserRequest userReq = {
        username: username,
        password: password,
        role: role,
        faculty: faculty == "" ? () : faculty
    };
    
    json|error response = httpClient->post("/api/users", userReq, headers);
    
    if response is json {
        io:println("User created successfully!");
        io:println("Username: " + username);
        io:println("Role: " + role.toString());
        if faculty != "" {
            io:println("Faculty: " + faculty);
        }
    } else {
        io:println("Error creating user: " + response.message());
    }
}

function viewAssetsByFaculty(http:Client httpClient, string? token) returns error? {
    string faculty = io:readln("Enter faculty name: ").trim();
    
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    Asset[]|error response = httpClient->get("/api/assets/faculty/" + faculty, headers);
    
    if response is Asset[] {
        io:println("\n=== Assets in " + faculty + " ===");
        if response.length() == 0 {
            io:println("No assets found for faculty: " + faculty);
        } else {
            foreach Asset asset in response {
                printAssetSummary(asset);
            }
        }
    } else {
        io:println("Error fetching assets: " + response.message());
    }
}

function checkOverdueAssets(http:Client httpClient, string? token) returns error? {
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    Asset[]|error response = httpClient->get("/api/assets/overdue", headers);
    
    if response is Asset[] {
        io:println("\n=== Assets with Overdue Maintenance ===");
        if response.length() == 0 {
            io:println("No assets with overdue maintenance found.");
        } else {
            foreach Asset asset in response {
                printAssetSummary(asset);
                io:println("  Overdue schedules:");
                foreach MaintenanceSchedule schedule in asset.schedules {
                    if schedule.isOverdue {
                        io:println("    - " + schedule.description + " (Due: " + schedule.nextDueDate.toString() + ")");
                    }
                }
            }
        }
    } else {
        io:println("Error fetching overdue assets: " + response.message());
    }
}

function viewSpecificAsset(http:Client httpClient, string? token) returns error? {
    string assetTag = io:readln("Enter asset tag: ").trim();
    
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    Asset|error response = httpClient->get("/api/assets/" + assetTag, headers);
    
    if response is Asset {
        printDetailedAsset(response);
    } else {
        io:println("Asset not found or error occurred: " + response.message());
    }
}

function addNewAsset(http:Client httpClient, string? token) returns error? {
    io:println("\n=== Add New Asset ===");
    string assetTag = io:readln("Asset Tag: ").trim();
    string name = io:readln("Name: ").trim();
    string faculty = io:readln("Faculty: ").trim();
    string department = io:readln("Department: ").trim();
    
    time:Civil currentDate = {year: 2024, month: 9, day: 21, hour: 0, minute: 0, second: 0};
    
    Asset newAsset = {
        assetTag: assetTag,
        name: name,
        faculty: faculty,
        department: department,
        status: ACTIVE,
        acquiredDate: currentDate,
        components: {},
        schedules: {},
        workOrders: {}
    };
    
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    Asset|error response = httpClient->post("/api/assets", newAsset, headers);
    
    if response is Asset {
        io:println("Asset added successfully and saved to file!");
        printAssetSummary(response);
    } else {
        io:println("Error adding asset: " + response.message());
    }
}

function updateAsset(http:Client httpClient, string? token) returns error? {
    string assetTag = io:readln("Enter asset tag to update: ").trim();
    
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    Asset|error existingAsset = httpClient->get("/api/assets/" + assetTag, headers);
    
    if existingAsset is error {
        io:println("Asset not found: " + existingAsset.message());
        return;
    }
    
    io:println("Current asset details:");
    printDetailedAsset(existingAsset);
    
    string newName = io:readln("New name (press enter to keep current): ").trim();
    string newStatus = io:readln("New status [ACTIVE/UNDER_REPAIR/DISPOSED] (press enter to keep current): ").trim();
    
    Asset updatedAsset = existingAsset;
    if newName != "" {
        updatedAsset.name = newName;
    }
    if newStatus != "" {
        match newStatus.toUpperAscii() {
            "ACTIVE" => { updatedAsset.status = ACTIVE; }
            "UNDER_REPAIR" => { updatedAsset.status = UNDER_REPAIR; }
            "DISPOSED" => { updatedAsset.status = DISPOSED; }
        }
    }
    
    Asset|error response = httpClient->put("/api/assets/" + assetTag, updatedAsset, headers);
    
    if response is Asset {
        io:println("Asset updated successfully and saved to file!");
        printDetailedAsset(response);
    } else {
        io:println("Error updating asset: " + response.message());
    }
}

function deleteAsset(http:Client httpClient, string? token) returns error? {
    string assetTag = io:readln("Enter asset tag to delete: ").trim();
    string confirm = io:readln("Are you sure? (y/N): ").trim();
    
    if confirm.toLowerAscii() != "y" {
        io:println("Delete cancelled");
        return;
    }
    
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    http:Response|error response = httpClient->delete("/api/assets/" + assetTag, headers = headers);
    
    if response is http:Response {
        io:println("Asset deleted successfully and saved to file!");
    } else {
        io:println("Error deleting asset: " + response.message());
    }
}

function addComponent(http:Client httpClient, string? token) returns error? {
    string assetTag = io:readln("Enter asset tag: ").trim();
    string componentId = io:readln("Component ID: ").trim();
    string componentName = io:readln("Component name: ").trim();
    string description = io:readln("Description: ").trim();
    
    Component newComponent = {
        componentId: componentId,
        name: componentName,
        description: description,
        status: "ACTIVE"
    };
    
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    Component|error response = httpClient->post("/api/assets/" + assetTag + "/components", newComponent, headers);
    
    if response is Component {
        io:println("Component added successfully and saved to file!");
    } else {
        io:println("Error adding component: " + response.message());
    }
}

function addMaintenanceSchedule(http:Client httpClient, string? token) returns error? {
    string assetTag = io:readln("Enter asset tag: ").trim();
    string scheduleId = io:readln("Schedule ID: ").trim();
    string description = io:readln("Description: ").trim();
    string frequency = io:readln("Frequency (QUARTERLY/YEARLY): ").trim();
    
    time:Civil futureDate = {year: 2025, month: 3, day: 15, hour: 0, minute: 0, second: 0};
    
    MaintenanceSchedule newSchedule = {
        scheduleId: scheduleId,
        description: description,
        frequency: frequency,
        nextDueDate: futureDate,
        isOverdue: false
    };
    
    string tokenToUse = "";
    if token is string {
        tokenToUse = token;
    }
    map<string> headers = {"Authorization": tokenToUse};
    MaintenanceSchedule|error response = httpClient->post("/api/assets/" + assetTag + "/schedules", newSchedule, headers);
    
    if response is MaintenanceSchedule {
        io:println("Maintenance schedule added successfully and saved to file!");
    } else {
        io:println("Error adding schedule: " + response.message());
    }
}

function printAssetSummary(Asset asset) {
    io:println("• " + asset.assetTag + " - " + asset.name + " [" + asset.status.toString() + "]");
    io:println("  Faculty: " + asset.faculty + " | Department: " + asset.department);
}

function printDetailedAsset(Asset asset) {
    io:println("\n=== Asset Details ===");
    io:println("Tag: " + asset.assetTag);
    io:println("Name: " + asset.name);
    io:println("Faculty: " + asset.faculty);
    io:println("Department: " + asset.department);
    io:println("Status: " + asset.status.toString());
    io:println("Acquired: " + asset.acquiredDate.toString());
    
    if asset.components.length() > 0 {
        io:println("\nComponents:");
        foreach Component component in asset.components {
            io:println("  • " + component.name + " (" + component.componentId + ") - " + component.description);
        }
    }
    
    if asset.schedules.length() > 0 {
        io:println("\nMaintenance Schedules:");
        foreach MaintenanceSchedule schedule in asset.schedules {
            string overdueStatus = schedule.isOverdue ? " [OVERDUE]" : " [OK]";
            io:println("  • " + schedule.description + " - " + schedule.frequency + overdueStatus);
            io:println("    Next due: " + schedule.nextDueDate.toString());
        }
    }
    
    if asset.workOrders.length() > 0 {
        io:println("\nWork Orders:");
        foreach var wo in asset.workOrders {
            io:println("  • Work Order: " + wo.toString());
        }
    }
}