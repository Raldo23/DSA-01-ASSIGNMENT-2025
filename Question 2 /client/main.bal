import ballerina/io;
import ballerina/grpc;

public function main() returns error? {
    io:println("=== Car Rental gRPC Client ===");
    io:println("Connecting to server at localhost:9090...");
    
    CarRentalServiceClient carRentalClient = check new ("http://localhost:9090");
    
    io:println("Connected successfully!");
    io:println("");
    
    string? currentToken = ();
    UserRole? currentRole = ();
    
    while true {
        if currentToken is () {
            io:println("--- Authentication Required ---");
            io:println("Please login to continue:");
            
            string username = io:readln("Username: ").trim();
            if username == "" {
                io:println("Username cannot be empty. Please try again.");
                continue;
            }
            string password = io:readln("Password: ").trim();
            
            LoginRequest loginReq = {username, password};
            
            LoginResponse|grpc:Error loginResp = carRentalClient->Login(loginReq);
            
            if loginResp is LoginResponse && loginResp.success {
                currentToken = loginResp.token;
                currentRole = loginResp.role;
                io:println("Login successful! Role: " + loginResp.role.toString());
                io:println("Token: " + loginResp.token);
            } else {
                string errorMsg = loginResp is LoginResponse ? loginResp.message : "Connection error";
                io:println("Login failed: " + errorMsg);
                continue;
            }
        }
        
        io:println("");
        io:println("--- Main Menu ---");
        io:println("1. List available cars");
        io:println("2. Search car by plate");
        io:println("3. View cart");
        
        if currentRole == CUSTOMER {
            io:println("4. Add car to cart");
            io:println("5. Place reservation");
        }
        
        if currentRole == ADMIN {
            io:println("6. Add new car");
            io:println("7. Update car");
            io:println("8. Remove car");
            io:println("9. Create user");
            io:println("10. List reservations");
        }
        
        io:println("0. Logout");
        
        string choice = io:readln("Enter your choice: ").trim();
        
        match choice {
            "1" => {
                check listAvailableCars(carRentalClient, currentToken);
            }
            "2" => {
                check searchCar(carRentalClient, currentToken);
            }
            "3" => {
                check viewCart(carRentalClient, currentToken);
            }
            "4" => {
                if currentRole == CUSTOMER {
                    check addToCart(carRentalClient, currentToken);
                } else {
                    io:println("Access denied. Customer access required.");
                }
            }
            "5" => {
                if currentRole == CUSTOMER {
                    check placeReservation(carRentalClient, currentToken);
                } else {
                    io:println("Access denied. Customer access required.");
                }
            }
            "6" => {
                if currentRole == ADMIN {
                    check addCar(carRentalClient, currentToken);
                } else {
                    io:println("Access denied. Admin access required.");
                }
            }
            "7" => {
                if currentRole == ADMIN {
                    check updateCar(carRentalClient, currentToken);
                } else {
                    io:println("Access denied. Admin access required.");
                }
            }
            "8" => {
                if currentRole == ADMIN {
                    check removeCar(carRentalClient, currentToken);
                } else {
                    io:println("Access denied. Admin access required.");
                }
            }
            "9" => {
                if currentRole == ADMIN {
                    check createUser(carRentalClient, currentToken);
                } else {
                    io:println("Access denied. Admin access required.");
                }
            }
            "10" => {
                if currentRole == ADMIN {
                    check listReservations(carRentalClient, currentToken);
                } else {
                    io:println("Access denied. Admin access required.");
                }
            }
            "0" => {
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