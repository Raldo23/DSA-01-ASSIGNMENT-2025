import ballerina/grpc;
import ballerina/time;
import ballerina/uuid;
import ballerina/log;
import ballerina/io;
import ballerina/file;


const string CARS_FILE = "data/cars.json";
const string USERS_FILE = "data/users.json";
const string RESERVATIONS_FILE = "data/reservations.json";
const string CARTS_FILE = "data/carts.json";

// from data/...
map<Car> cars = {};
map<User> users = {};
map<CartItem[]> userCarts = {};
map<Reservation> reservations = {};
map<string> activeTokens = {};

@grpc:ServiceDescriptor {
    descriptor: CAR_RENTAL_DESC
}
service "CarRentalService" on new grpc:Listener(9090) {

function init() {
    error? dirResult = ensureDataDirectory();
    if dirResult is error {
        io:println("Error creating data directory: " + dirResult.message());
    }
    
    error? loadResult = loadDataFromFiles();
    if loadResult is error {
        io:println("Error loading data from files: " + loadResult.message());
        io:println("Initializing with sample data...");
        initializeSampleData();
    } else {
        io:println("Data loaded successfully from JSON files");
        if cars.length() == 0 && users.length() == 0 {
            io:println("No existing data found, initializing sample data...");
            initializeSampleData();
        }
    }
}

    remote function AddCar(AddCarRequest req) returns AddCarResponse|grpc:Error {
        string|error authResult = authenticateAdmin(req.admin_token);
        if authResult is error {
            return {success: false, message: "Unauthorized: " + authResult.message(), car_plate: ""};
        }

        if req.car.plate == "" || req.car.make == "" || req.car.model == "" {
            return {success: false, message: "Missing required car information", car_plate: ""};
        }

        if cars.hasKey(req.car.plate) {
            return {success: false, message: "Car with plate " + req.car.plate + " already exists", car_plate: ""};
        }

        cars[req.car.plate] = req.car;
        error? saveResult = saveCarsToFile();
        if saveResult is error {
            log:printError("Failed to save cars to file", saveResult);
        }
        
        log:printInfo("Car added: " + req.car.plate + " by admin: " + authResult);
        return {
            success: true, 
            message: "Car added successfully and saved to file", 
            car_plate: req.car.plate
        };
    }

    remote function UpdateCar(UpdateCarRequest req) returns UpdateCarResponse|grpc:Error {
        string|error authResult = authenticateAdmin(req.admin_token);
        if authResult is error {
            return {success: false, message: "Unauthorized: " + authResult.message(), updated_car: {}};
        }

        if !cars.hasKey(req.plate) {
            return {success: false, message: "Car not found", updated_car: {}};
        }

        req.updated_car.plate = req.plate;
        cars[req.plate] = req.updated_car;
        error? saveResult = saveCarsToFile();
        if saveResult is error {
            log:printError("Failed to save cars to file", saveResult);
        }

        log:printInfo("Car updated: " + req.plate + " by admin: " + authResult);
        return {
            success: true,
            message: "Car updated successfully and saved to file",
            updated_car: req.updated_car
        };
    }

    remote function RemoveCar(RemoveCarRequest req) returns RemoveCarResponse|grpc:Error {
        string|error authResult = authenticateAdmin(req.admin_token);
        if authResult is error {
            return {success: false, message: "Unauthorized: " + authResult.message(), remaining_cars: []};
        }

        if !cars.hasKey(req.plate) {
            return {success: false, message: "Car not found", remaining_cars: []};
        }

        _ = cars.remove(req.plate);
        error? saveResult = saveCarsToFile();
        if saveResult is error {
            log:printError("Failed to save cars to file", saveResult);
        }

        Car[] remainingCars = cars.toArray();
        
        log:printInfo("Car removed: " + req.plate + " by admin: " + authResult);
        return {
            success: true,
            message: "Car removed successfully and saved to file",
            remaining_cars: remainingCars
        };
    }

    remote function CreateUser(CreateUserRequest req) returns CreateUserResponse|grpc:Error {
        string|error authResult = authenticateAdmin(req.admin_token);
        if authResult is error {
            return {success: false, message: "Unauthorized: " + authResult.message(), user_id: ""};
        }

        if req.user.user_id == "" {
            req.user.user_id = uuid:createType1AsString();
        }

        if users.hasKey(req.user.user_id) {
            return {success: false, message: "User already exists", user_id: ""};
        }

        users[req.user.user_id] = req.user;
        userCarts[req.user.user_id] = [];
        error? saveUsersResult = saveUsersToFile();
        error? saveCartsResult = saveCartsToFile();
        if saveUsersResult is error {
            log:printError("Failed to save users to file", saveUsersResult);
        }
        if saveCartsResult is error {
            log:printError("Failed to save carts to file", saveCartsResult);
        }
        
        log:printInfo("User created: " + req.user.user_id);
        return {
            success: true,
            message: "User created successfully and saved to file",
            user_id: req.user.user_id
        };
    }

    remote function ListReservations(ListReservationsRequest req) returns ListReservationsResponse|grpc:Error {
        string|error authResult = authenticateAdmin(req.admin_token);
        if authResult is error {
            return {success: false, reservations: [], message: "Unauthorized: " + authResult.message()};
        }

        Reservation[] filteredReservations = [];
        
        foreach Reservation reservation in reservations {
            boolean include = true;
            
            if req.filter_by_customer != "" && reservation.customer_id != req.filter_by_customer {
                include = false;
            }
            
            if req.filter_by_status != "" && reservation.status.toString() != req.filter_by_status {
                include = false;
            }
            
            if include {
                filteredReservations.push(reservation);
            }
        }

        return {
            success: true,
            reservations: filteredReservations,
            message: "Found " + filteredReservations.length().toString() + " reservations"
        };
    }

    remote function ListAvailableCars(ListAvailableCarsRequest req) returns ListAvailableCarsResponse|grpc:Error {
        string|error authResult = authenticateCustomer(req.customer_token);
        if authResult is error {
            return {success: false, cars: [], message: "Unauthorized: " + authResult.message()};
        }

        Car[] availableCars = [];
        
        foreach Car car in cars {
            if car.status == AVAILABLE {
                boolean include = true;
                
                if req.filter_text != "" {
                    string searchText = req.filter_text.toLowerAscii();
                    if !(car.make.toLowerAscii().includes(searchText) || 
                          car.model.toLowerAscii().includes(searchText)) {
                        include = false;
                    }
                }
                
                if req.filter_year > 0 && car.year != req.filter_year {
                    include = false;
                }
                
                if req.start_date != "" && req.end_date != "" {
                    if !isCarAvailableForDates(car.plate, req.start_date, req.end_date) {
                        include = false;
                    }
                }
                
                if include {
                    availableCars.push(car);
                }
            }
        }

        return {
            success: true,
            cars: availableCars,
            message: "Found " + availableCars.length().toString() + " available cars"
        };
    }

    remote function SearchCar(SearchCarRequest req) returns SearchCarResponse|grpc:Error {
        string|error authResult = authenticateCustomer(req.customer_token);
        if authResult is error {
            return {found: false, car: {}, message: "Unauthorized: " + authResult.message()};
        }

        Car? car = cars[req.plate];
        if car is () {
            return {found: false, car: {}, message: "Car not found"};
        }

        if car.status != AVAILABLE {
            return {found: false, car: car, message: "Car is not available for rental"};
        }

        return {found: true, car: car, message: "Car found and available"};
    }

    remote function AddToCart(AddToCartRequest req) returns AddToCartResponse|grpc:Error {
        string|error authResult = authenticateCustomer(req.customer_token);
        if authResult is error {
            return {success: false, message: "Unauthorized: " + authResult.message(), cart_item: {}, cart_total: 0.0};
        }

        Car? car = cars[req.plate];
        if car is () {
            return {success: false, message: "Car not found", cart_item: {}, cart_total: 0.0};
        }

        if car.status != AVAILABLE {
            return {success: false, message: "Car is not available", cart_item: {}, cart_total: 0.0};
        }

        string|error dateValidation = validateDates(req.start_date, req.end_date);
        if dateValidation is error {
            return {success: false, message: dateValidation.message(), cart_item: {}, cart_total: 0.0};
        }

        if !isCarAvailableForDates(req.plate, req.start_date, req.end_date) {
            return {success: false, message: "Car is not available for selected dates", cart_item: {}, cart_total: 0.0};
        }

        int rentalDays = calculateDays(req.start_date, req.end_date);
        float estimatedPrice = <float>rentalDays * car.daily_price;

        CartItem cartItem = {
            plate: req.plate,
            start_date: req.start_date,
            end_date: req.end_date,
            estimated_price: estimatedPrice,
            rental_days: rentalDays
        };

        CartItem[] userCart = userCarts[authResult] ?: [];
        userCart.push(cartItem);
        userCarts[authResult] = userCart;
        error? saveResult = saveCartsToFile();
        if saveResult is error {
            log:printError("Failed to save carts to file", saveResult);
        }

        float cartTotal = 0.0;
        foreach CartItem item in userCart {
            cartTotal += item.estimated_price;
        }

        return {
            success: true,
            message: "Car added to cart successfully and saved to file",
            cart_item: cartItem,
            cart_total: cartTotal
        };
    }

    remote function PlaceReservation(PlaceReservationRequest req) returns PlaceReservationResponse|grpc:Error {
        string|error authResult = authenticateCustomer(req.customer_token);
        if authResult is error {
            return {success: false, message: "Unauthorized: " + authResult.message(), reservations: [], total_amount: 0.0, confirmation_number: ""};
        }

        CartItem[] userCart = userCarts[authResult] ?: [];
        if userCart.length() == 0 {
            return {success: false, message: "Cart is empty", reservations: [], total_amount: 0.0, confirmation_number: ""};
        }

        foreach CartItem item in userCart {
            if !isCarAvailableForDates(item.plate, item.start_date, item.end_date) {
                return {success: false, message: "Car " + item.plate + " is no longer available for selected dates", reservations: [], total_amount: 0.0, confirmation_number: ""};
            }
        }

        Reservation[] createdReservations = [];
        float totalAmount = 0.0;
        string confirmationNumber = uuid:createType1AsString();

        foreach CartItem item in userCart {
            string reservationId = uuid:createType1AsString();
            time:Utc currentTime = time:utcNow();
            
            Reservation reservation = {
                reservation_id: reservationId,
                customer_id: authResult,
                plate: item.plate,
                start_date: item.start_date,
                end_date: item.end_date,
                total_price: item.estimated_price,
                status: CONFIRMED,
                created_at: time:utcToString(currentTime),
                pickup_location: req.pickup_location,
                return_location: req.return_location
            };

            reservations[reservationId] = reservation;
            createdReservations.push(reservation);
            totalAmount += item.estimated_price;
        }

        userCarts[authResult] = [];
        error? saveReservationsResult = saveReservationsToFile();
        error? saveCartsResult = saveCartsToFile();
        if saveReservationsResult is error {
            log:printError("Failed to save reservations to file", saveReservationsResult);
        }
        if saveCartsResult is error {
            log:printError("Failed to save carts to file", saveCartsResult);
        }

        log:printInfo("Reservation placed by customer: " + authResult + ", Total: " + totalAmount.toString());
        
        return {
            success: true,
            message: "Reservation placed successfully and saved to file",
            reservations: createdReservations,
            total_amount: totalAmount,
            confirmation_number: confirmationNumber
        };
    }

    remote function ViewCart(ViewCartRequest req) returns ViewCartResponse|grpc:Error {
        string|error authResult = authenticateCustomer(req.customer_token);
        if authResult is error {
            return {items: [], total_price: 0.0, total_items: 0};
        }

        CartItem[] userCart = userCarts[authResult] ?: [];
        float totalPrice = 0.0;
        
        foreach CartItem item in userCart {
            totalPrice += item.estimated_price;
        }

        return {
            items: userCart,
            total_price: totalPrice,
            total_items: userCart.length()
        };
    }

    remote function Login(LoginRequest req) returns LoginResponse|grpc:Error {
        if req.username == "admin" && req.password == "admin" {
            string token = uuid:createType1AsString();
            activeTokens[token] = "admin-001";
            
            time:Utc currentTime = time:utcNow();
            time:Utc expiryTime = time:utcAddSeconds(currentTime, 86400);
            
            return {
                success: true,
                message: "Admin login successful",
                token: token,
                role: ADMIN,
                user_id: "admin-001",
                expires_at: time:utcToString(expiryTime)
            };
        }
        
        if req.username == "customer1" && req.password == "customer1" {
            string token = uuid:createType1AsString();
            activeTokens[token] = "customer-001";
            
            time:Utc currentTime = time:utcNow();
            time:Utc expiryTime = time:utcAddSeconds(currentTime, 86400);
            
            return {
                success: true,
                message: "Customer login successful",
                token: token,
                role: CUSTOMER,
                user_id: "customer-001",
                expires_at: time:utcToString(expiryTime)
            };
        }

        return {
            success: false,
            message: "Invalid username or password",
            token: "",
            role: CUSTOMER,
            user_id: "",
            expires_at: ""
        };
    }
}

function loadDataFromFiles() returns error? {
    boolean carsLoaded = true;
    boolean usersLoaded = true;
    boolean reservationsLoaded = true;
    boolean cartsLoaded = true;
    
    error? loadCarsResult = loadCarsFromFile();
    if loadCarsResult is error {
        io:println("Cars loading failed: " + loadCarsResult.message());
        carsLoaded = false;
    }
    
    error? loadUsersResult = loadUsersFromFile();
    if loadUsersResult is error {
        io:println("Users loading failed: " + loadUsersResult.message());
        usersLoaded = false;
    }
    
    error? loadReservationsResult = loadReservationsFromFile();
    if loadReservationsResult is error {
        io:println("Reservations loading failed: " + loadReservationsResult.message());
        reservationsLoaded = false;
    }
    
    error? loadCartsResult = loadCartsFromFile();
    if loadCartsResult is error {
        io:println("Carts loading failed: " + loadCartsResult.message());
        cartsLoaded = false;
    }
    
    // Only return error if critical files (cars and users) failed to load AND they exist
    if (!carsLoaded && check file:test(CARS_FILE, file:EXISTS)) {
        return error("Failed to load existing cars file");
    }
    if (!usersLoaded && check file:test(USERS_FILE, file:EXISTS)) {
        return error("Failed to load existing users file");
    }
    
    return;
}

function loadCarsFromFile() returns error? {
    if !check file:test(CARS_FILE, file:EXISTS) {
        io:println("Cars file not found, will create with initial data");
        return error("Cars file does not exist");
    }
    
    string content = check io:fileReadString(CARS_FILE);
    if content.trim() == "" {
        io:println("Cars file is empty");
        return error("Cars file is empty");
    }
    
    json carsJson = check content.fromJsonString();
    
    if carsJson is map<json> {
        foreach [string, json] [plate, carJson] in carsJson.entries() {
            Car? car = parseCarFromJson(carJson);
            if car is Car {
                cars[plate] = car;
            }
        }
    }
    io:println("Loaded " + cars.length().toString() + " cars from file");
    return;
}


function loadUsersFromFile() returns error? {
    if !check file:test(USERS_FILE, file:EXISTS) {
        io:println("Users file not found, will create with initial data");
        return error("Users file does not exist");
    }
    
    string content = check io:fileReadString(USERS_FILE);
    if content.trim() == "" {
        io:println("Users file is empty");
        return error("Users file is empty");
    }
    
    json usersJson = check content.fromJsonString();
    
    if usersJson is map<json> {
        foreach [string, json] [userId, userJson] in usersJson.entries() {
            User? user = parseUserFromJson(userJson);
            if user is User {
                users[userId] = user;
            }
        }
    }
    io:println("Loaded " + users.length().toString() + " users from file");
    return;
}

function loadReservationsFromFile() returns error? {
    if !check file:test(RESERVATIONS_FILE, file:EXISTS) {
        io:println("Reservations file not found, starting with empty reservations");
        return;
    }
    
    string content = check io:fileReadString(RESERVATIONS_FILE);
    if content.trim() == "" {
        io:println("Reservations file is empty, starting with empty reservations");
        return;
    }
    
    json reservationsJson = check content.fromJsonString();
    
    if reservationsJson is map<json> {
        foreach [string, json] [resId, reservationJson] in reservationsJson.entries() {
            Reservation? reservation = parseReservationFromJson(reservationJson);
            if reservation is Reservation {
                reservations[resId] = reservation;
            }
        }
    }
    io:println("Loaded " + reservations.length().toString() + " reservations from file");
    return;
}

function loadCartsFromFile() returns error? {
    if !check file:test(CARTS_FILE, file:EXISTS) {
        io:println("Carts file not found, starting with empty carts");
        return;
    }
    
    string content = check io:fileReadString(CARTS_FILE);
    if content.trim() == "" {
        io:println("Carts file is empty, starting with empty carts");
        return;
    }
    
    json cartsJson = check content.fromJsonString();
    
    if cartsJson is map<json> {
        foreach [string, json] [userId, cartJson] in cartsJson.entries() {
            if cartJson is json[] {
                CartItem[] cartItems = [];
                foreach json itemJson in cartJson {
                    CartItem? item = parseCartItemFromJson(itemJson);
                    if item is CartItem {
                        cartItems.push(item);
                    }
                }
                userCarts[userId] = cartItems;
            }
        }
    }
    io:println("Loaded carts for " + userCarts.length().toString() + " users from file");
    return;
}

function saveCarsToFile() returns error? {
    check ensureDataDirectory();
    
    map<json> carsJson = {};
    foreach [string, Car] [plate, car] in cars.entries() {
        carsJson[plate] = convertCarToJson(car);
    }
    
    string jsonString = carsJson.toJsonString();
    check io:fileWriteString(CARS_FILE, jsonString);
}

function saveUsersToFile() returns error? {
    check ensureDataDirectory();
    
    map<json> usersJson = {};
    foreach [string, User] [userId, user] in users.entries() {
        usersJson[userId] = convertUserToJson(user);
    }
    
    string jsonString = usersJson.toJsonString();
    check io:fileWriteString(USERS_FILE, jsonString);
}

function saveReservationsToFile() returns error? {
    check ensureDataDirectory();
    
    map<json> reservationsJson = {};
    foreach [string, Reservation] [resId, reservation] in reservations.entries() {
        reservationsJson[resId] = convertReservationToJson(reservation);
    }
    
    string jsonString = reservationsJson.toJsonString();
    check io:fileWriteString(RESERVATIONS_FILE, jsonString);
}

function saveCartsToFile() returns error? {
    check ensureDataDirectory();
    
    map<json> cartsJson = {};
    foreach [string, CartItem[]] [userId, cartItems] in userCarts.entries() {
        json[] cartJson = [];
        foreach CartItem item in cartItems {
            cartJson.push(convertCartItemToJson(item));
        }
        cartsJson[userId] = cartJson;
    }
    
    string jsonString = cartsJson.toJsonString();
    check io:fileWriteString(CARTS_FILE, jsonString);
}

function ensureDataDirectory() returns error? {
    if !check file:test("data", file:EXISTS) {
        check file:createDir("data");
    }
}

// JSON parsing functions
function parseCarFromJson(json carJson) returns Car? {
    if carJson is map<json> {
        string? plate = carJson["plate"].toString();
        string? make = carJson["make"].toString();
        string? model = carJson["model"].toString();
        string? statusStr = carJson["status"].toString();
        
        if plate is string && make is string && model is string && statusStr is string {
            CarStatus status = statusStr == "UNAVAILABLE" ? UNAVAILABLE :
                              statusStr == "RENTED" ? RENTED :
                              statusStr == "MAINTENANCE" ? MAINTENANCE : AVAILABLE;
            
            return {
                plate: plate,
                make: make,
                model: model,
                year: <int>carJson["year"],
                daily_price: <float>carJson["daily_price"],
                mileage: <int>carJson["mileage"],
                status: status,
                location: carJson["location"].toString(),
                features: <string[]>carJson["features"]
            };
        }
    }
    return ();
}

function parseUserFromJson(json userJson) returns User? {
    if userJson is map<json> {
        string? userId = userJson["user_id"].toString();
        string? username = userJson["username"].toString();
        string? roleStr = userJson["role"].toString();
        
        if userId is string && username is string && roleStr is string {
            UserRole role = roleStr == "ADMIN" ? ADMIN : CUSTOMER;
            
            return {
                user_id: userId,
                username: username,
                email: userJson["email"].toString(),
                full_name: userJson["full_name"].toString(),
                role: role,
                phone: userJson["phone"].toString(),
                license_number: userJson["license_number"].toString()
            };
        }
    }
    return ();
}

function parseReservationFromJson(json reservationJson) returns Reservation? {
    if reservationJson is map<json> {
        string? resId = reservationJson["reservation_id"].toString();
        string? statusStr = reservationJson["status"].toString();
        
        if resId is string && statusStr is string {
            ReservationStatus status = statusStr == "PENDING" ? PENDING :
                                      statusStr == "CANCELLED" ? CANCELLED :
                                      statusStr == "COMPLETED" ? COMPLETED : CONFIRMED;
            
            return {
                reservation_id: resId,
                customer_id: reservationJson["customer_id"].toString(),
                plate: reservationJson["plate"].toString(),
                start_date: reservationJson["start_date"].toString(),
                end_date: reservationJson["end_date"].toString(),
                total_price: <float>reservationJson["total_price"],
                status: status,
                created_at: reservationJson["created_at"].toString(),
                pickup_location: reservationJson["pickup_location"].toString(),
                return_location: reservationJson["return_location"].toString()
            };
        }
    }
    return ();
}

function parseCartItemFromJson(json itemJson) returns CartItem? {
    if itemJson is map<json> {
        return {
            plate: itemJson["plate"].toString(),
            start_date: itemJson["start_date"].toString(),
            end_date: itemJson["end_date"].toString(),
            estimated_price: <float>itemJson["estimated_price"],
            rental_days: <int>itemJson["rental_days"]
        };
    }
    return ();
}

// JSON conversion functions
function convertCarToJson(Car car) returns json {
    return {
        "plate": car.plate,
        "make": car.make,
        "model": car.model,
        "year": car.year,
        "daily_price": car.daily_price,
        "mileage": car.mileage,
        "status": car.status.toString(),
        "location": car.location,
        "features": car.features
    };
}

function convertUserToJson(User user) returns json {
    return {
        "user_id": user.user_id,
        "username": user.username,
        "email": user.email,
        "full_name": user.full_name,
        "role": user.role.toString(),
        "phone": user.phone,
        "license_number": user.license_number
    };
}

function convertReservationToJson(Reservation reservation) returns json {
    return {
        "reservation_id": reservation.reservation_id,
        "customer_id": reservation.customer_id,
        "plate": reservation.plate,
        "start_date": reservation.start_date,
        "end_date": reservation.end_date,
        "total_price": reservation.total_price,
        "status": reservation.status.toString(),
        "created_at": reservation.created_at,
        "pickup_location": reservation.pickup_location,
        "return_location": reservation.return_location
    };
}

function convertCartItemToJson(CartItem item) returns json {
    return {
        "plate": item.plate,
        "start_date": item.start_date,
        "end_date": item.end_date,
        "estimated_price": item.estimated_price,
        "rental_days": item.rental_days
    };
}

// Helper functions (unchanged)
function authenticateAdmin(string token) returns string|error {
    string? userId = activeTokens[token];
    if userId is () {
        return error("Invalid token");
    }

    User? user = users[userId];
    if user is () {
        return error("User not found");
    }

    if user.role != ADMIN {
        return error("Admin access required");
    }

    return userId;
}

function authenticateCustomer(string token) returns string|error {
    string? userId = activeTokens[token];
    if userId is () {
        return error("Invalid token");
    }

    User? user = users[userId];
    if user is () {
        return error("User not found");
    }

    return userId;
}

function validateDates(string startDate, string endDate) returns string|error {
    if startDate.length() != 10 || endDate.length() != 10 {
        return error("Invalid date format. Use YYYY-MM-DD");
    }

    if startDate >= endDate {
        return error("End date must be after start date");
    }

    return "Valid";
}

function calculateDays(string startDate, string endDate) returns int {
    return 3; // Simplified for demo
}

function isCarAvailableForDates(string plate, string startDate, string endDate) returns boolean {
    foreach Reservation reservation in reservations {
        if reservation.plate == plate && reservation.status == CONFIRMED {
            if !(endDate <= reservation.start_date || startDate >= reservation.end_date) {
                return false;
            }
        }
    }
    return true;
}

function initializeSampleData() {
    User adminUser = {
        user_id: "admin-001",
        username: "admin",
        email: "admin@carrental.com",
        full_name: "System Administrator",
        role: ADMIN,
        phone: "+1234567890",
        license_number: ""
    };
    users["admin-001"] = adminUser;
    userCarts["admin-001"] = [];

    User customerUser = {
        user_id: "customer-001",
        username: "customer1",
        email: "customer1@email.com",
        full_name: "John Doe",
        role: CUSTOMER,
        phone: "+1987654321",
        license_number: "DL123456789"
    };
    users["customer-001"] = customerUser;
    userCarts["customer-001"] = [];

    Car car1 = {
        plate: "ABC123",
        make: "Toyota",
        model: "Camry",
        year: 2022,
        daily_price: 50.0,
        mileage: 15000,
        status: AVAILABLE,
        location: "Downtown Branch",
        features: ["GPS", "Bluetooth", "AC", "Backup Camera"]
    };
    cars["ABC123"] = car1;

    Car car2 = {
        plate: "XYZ789",
        make: "Honda",
        model: "Civic",
        year: 2023,
        daily_price: 45.0,
        mileage: 8000,
        status: AVAILABLE,
        location: "Airport Branch",
        features: ["GPS", "Bluetooth", "AC"]
    };
    cars["XYZ789"] = car2;

    // Save initial data to files
    error? saveCarsResult = saveCarsToFile();
    error? saveUsersResult = saveUsersToFile();
    error? saveCartsResult = saveCartsToFile();
    error? saveReservationsResult = saveReservationsToFile();
    
    if saveCarsResult is error || saveUsersResult is error || 
       saveCartsResult is error || saveReservationsResult is error {
        io:println("Warning: Failed to save some initial data to files");
    } else {
        io:println("Sample data initialized and saved to files:");
        io:println("- Admin user: admin (password: admin)");
        io:println("- Customer user: customer1 (password: customer1)");
        io:println("- Sample cars: ABC123, XYZ789");
        io:println("- Data saved to: data/cars.json, data/users.json, data/carts.json, data/reservations.json");
    }
}