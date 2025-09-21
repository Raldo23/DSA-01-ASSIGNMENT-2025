import ballerina/io;
import ballerina/grpc;
import ballerina/regex;

function cleanNumericInput(string input) returns string {
    string cleaned = regex:replaceAll(input, " ", "");
    cleaned = regex:replaceAll(cleaned, ",", "");
    return cleaned;
}

function listAvailableCars(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    
    ListAvailableCarsRequest req = {
        customer_token: tokenToUse,
        filter_text: "",
        filter_year: 0,
        start_date: "",
        end_date: ""
    };
    
    // Ask for optional filters
    io:println("\n=== List Available Cars ===");
    string filterText = io:readln("Filter by make/model (Select 'optional', or 'all'): ").trim();
    if filterText != "" && filterText.toLowerAscii() != "all" {
        req.filter_text = filterText;
    }
    
    string filterYear = io:readln("Filter by year (Select 'optional', or 'any'): ").trim();
    if filterYear != "" && filterYear.toLowerAscii() != "any" {
        int|error year = int:fromString(filterYear);
        if year is int {
            req.filter_year = year;
        }
    }
    
    ListAvailableCarsResponse|grpc:Error response = carClient->ListAvailableCars(req);
    
    if response is ListAvailableCarsResponse {
        io:println("\n" + response.message);
        if response.success && response.cars.length() > 0 {
            foreach Car car in response.cars {
                printCarDetails(car);
            }
        } else {
            io:println("No cars available matching your criteria.");
        }
    } else {
        io:println("Error: " + response.message());
    }
}

function searchCar(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    string plate = io:readln("Enter car plate number: ").trim();
    
    if plate == "" {
        io:println("Plate number cannot be empty.");
        return;
    }
    
    SearchCarRequest req = {
        customer_token: tokenToUse,
        plate: plate
    };
    
    SearchCarResponse|grpc:Error response = carClient->SearchCar(req);
    
    if response is SearchCarResponse {
        io:println("\n=== Search Results ===");
        if response.found {
            io:println("Car found!");
            printCarDetails(response.car);
        } else {
            io:println("Result: " + response.message);
        }
    } else {
        io:println("Error: " + response.message());
    }
}

function viewCart(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    
    ViewCartRequest req = {
        customer_token: tokenToUse
    };
    
    ViewCartResponse|grpc:Error response = carClient->ViewCart(req);
    
    if response is ViewCartResponse {
        io:println("\n=== Your Cart ===");
        if response.total_items > 0 {
            io:println("Items in cart: " + response.total_items.toString());
            io:println("Total price: $" + response.total_price.toString());
            
            foreach CartItem item in response.items {
                io:println("\n• Car: " + item.plate);
                io:println("  Rental period: " + item.start_date + " to " + item.end_date);
                io:println("  Days: " + item.rental_days.toString());
                io:println("  Price: $" + item.estimated_price.toString());
            }
        } else {
            io:println("Your cart is empty.");
        }
    } else {
        io:println("Error: " + response.message());
    }
}

function addToCart(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    
    io:println("\n=== Add Car to Cart ===");
    string plate = io:readln("Enter car plate: ").trim();
    string startDate = io:readln("Start date (YYYY-MM-DD): ").trim();
    string endDate = io:readln("End date (YYYY-MM-DD): ").trim();
    
    if plate == "" || startDate == "" || endDate == "" {
        io:println("All fields are required.");
        return;
    }
    
    AddToCartRequest req = {
        customer_token: tokenToUse,
        plate: plate,
        start_date: startDate,
        end_date: endDate
    };
    
    AddToCartResponse|grpc:Error response = carClient->AddToCart(req);
    
    if response is AddToCartResponse {
        if response.success {
            io:println("Success: " + response.message);
            io:println("Cart total: $" + response.cart_total.toString());
        } else {
            io:println("Failed: " + response.message);
        }
    } else {
        io:println("Error: " + response.message());
    }
}

function placeReservation(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    
    io:println("\n=== Place Reservation ===");
    string pickupLocation = io:readln("Pickup location: ").trim();
    string returnLocation = io:readln("Return location: ").trim();
    
    PlaceReservationRequest req = {
        customer_token: tokenToUse,
        pickup_location: pickupLocation,
        return_location: returnLocation
    };
    
    PlaceReservationResponse|grpc:Error response = carClient->PlaceReservation(req);
    
    if response is PlaceReservationResponse {
        if response.success {
            io:println("Success: " + response.message);
            io:println("Total amount: $" + response.total_amount.toString());
            io:println("Confirmation number: " + response.confirmation_number);
            
            io:println("\nReservation details:");
            foreach Reservation reservation in response.reservations {
                io:println("• Reservation ID: " + reservation.reservation_id);
                io:println("  Car: " + reservation.plate);
                io:println("  Period: " + reservation.start_date + " to " + reservation.end_date);
                io:println("  Price: $" + reservation.total_price.toString());
            }
        } else {
            io:println("Failed: " + response.message);
        }
    } else {
        io:println("Error: " + response.message());
    }
}

function addCar(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    
    io:println("\n=== Add New Car ===");
    io:println("Note: Enter numeric values without spaces or commas");
    io:println("Example: For 300,000 enter '300000'");
    io:println("");
    
    string plate = io:readln("Car plate: ").trim();
    string make = io:readln("Make: ").trim();
    string model = io:readln("Model: ").trim();
    string yearStr = io:readln("Year: ").trim();
    string priceStr = io:readln("Daily price (no spaces/commas): ").trim();
    string mileageStr = io:readln("Mileage (no spaces/commas): ").trim();
    string location = io:readln("Location: ").trim();
    
    if plate == "" || make == "" || model == "" || yearStr == "" || priceStr == "" {
        io:println("All required fields must be filled.");
        return;
    }
    
    string cleanYearStr = cleanNumericInput(yearStr);
    string cleanPriceStr = cleanNumericInput(priceStr);
    string cleanMileageStr = cleanNumericInput(mileageStr);
    
    int|error year = int:fromString(cleanYearStr);
    float|error price = float:fromString(cleanPriceStr);
    int|error mileage = int:fromString(cleanMileageStr);
    
    if year is error {
        io:println("Invalid year: '" + yearStr + "'. Please enter a valid number (e.g., 2020)");
        return;
    }
    
    if price is error {
        io:println("Invalid price: '" + priceStr + "'. Please enter a valid number (e.g., 50000)");
        return;
    }
    
    if mileage is error {
        io:println("Invalid mileage: '" + mileageStr + "'. Please enter a valid number (e.g., 25000)");
        return;
    }
    
    Car newCar = {
        plate: plate,
        make: make,
        model: model,
        year: year,
        daily_price: price,
        mileage: mileage,
        status: AVAILABLE,
        location: location,
        features: ["Standard Equipment"]
    };
    
    AddCarRequest req = {
        admin_token: tokenToUse,
        car: newCar
    };
    
    io:println("\nSending request to add car...");
    
    AddCarResponse|grpc:Error response = carClient->AddCar(req);
    
    if response is AddCarResponse {
        if response.success {
            io:println("Success: " + response.message);
            io:println("Car plate: " + response.car_plate);
            io:println("Car details saved to data/cars.json");
        } else {
            io:println("Failed: " + response.message);
        }
    } else {
        io:println("Error: " + response.message());
    }
}

function updateCar(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    
    io:println("\n=== Update Car ===");
    string plate = io:readln("Car plate to update: ").trim();
    
    if plate == "" {
        io:println("Car plate is required.");
        return;
    }
    
    SearchCarRequest searchReq = {
        customer_token: tokenToUse,
        plate: plate
    };
    
    SearchCarResponse|grpc:Error searchResp = carClient->SearchCar(searchReq);
    
    Car currentCar = {};
    if searchResp is SearchCarResponse && searchResp.found {
        currentCar = searchResp.car;
        io:println("\nCurrent car details:");
        printCarDetails(currentCar);
    } else {
        io:println("Car not found or not accessible. Using default values for update.");
        currentCar = {
            plate: plate,
            make: "Unknown",
            model: "Unknown",
            year: 2020,
            daily_price: 50.0,
            mileage: 0,
            status: AVAILABLE,
            location: "Unknown",
            features: ["Standard Equipment"]
        };
    }
    
    io:println("\nEnter new values (leave empty to keep current):");
    
    string newPriceStr = io:readln("New daily price (current: " + currentCar.daily_price.toString() + "): ").trim();
    string newStatus = io:readln("New status (AVAILABLE/UNAVAILABLE/MAINTENANCE, current: " + currentCar.status.toString() + "): ").trim();
    string newLocation = io:readln("New location (current: " + currentCar.location + "): ").trim();
    
    Car updatedCar = currentCar;
    updatedCar.plate = plate;
    
    if newPriceStr != "" {
        string cleanPriceStr = cleanNumericInput(newPriceStr);
        float|error newPrice = float:fromString(cleanPriceStr);
        if newPrice is float {
            updatedCar.daily_price = newPrice;
        } else {
            io:println("Invalid price format, keeping current price.");
        }
    }
    
    if newStatus != "" {
        if newStatus.toUpperAscii() == "UNAVAILABLE" {
            updatedCar.status = UNAVAILABLE;
        } else if newStatus.toUpperAscii() == "MAINTENANCE" {
            updatedCar.status = MAINTENANCE;
        } else if newStatus.toUpperAscii() == "AVAILABLE" {
            updatedCar.status = AVAILABLE;
        } else {
            io:println("Invalid status, keeping current status.");
        }
    }
    
    if newLocation != "" {
        updatedCar.location = newLocation;
    }
    
    UpdateCarRequest req = {
        admin_token: tokenToUse,
        plate: plate,
        updated_car: updatedCar
    };
    
    UpdateCarResponse|grpc:Error response = carClient->UpdateCar(req);
    
    if response is UpdateCarResponse {
        if response.success {
            io:println("Success: " + response.message);
            io:println("Updated car details:");
            printCarDetails(response.updated_car);
        } else {
            io:println("Failed: " + response.message);
        }
    } else {
        io:println("Error: " + response.message());
    }
}

function removeCar(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    
    io:println("\n=== Remove Car ===");
    string plate = io:readln("Car plate to remove: ").trim();
    string confirm = io:readln("Are you sure? (y/N): ").trim();
    
    if plate == "" {
        io:println("Car plate is required.");
        return;
    }
    
    if confirm.toLowerAscii() != "y" {
        io:println("Remove cancelled.");
        return;
    }
    
    RemoveCarRequest req = {
        admin_token: tokenToUse,
        plate: plate
    };
    
    RemoveCarResponse|grpc:Error response = carClient->RemoveCar(req);
    
    if response is RemoveCarResponse {
        if response.success {
            io:println("Success: " + response.message);
            io:println("Remaining cars: " + response.remaining_cars.length().toString());
        } else {
            io:println("Failed: " + response.message);
        }
    } else {
        io:println("Error: " + response.message());
    }
}

function createUser(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    
    io:println("\n=== Create New User ===");
    string username = io:readln("Username: ").trim();
    string email = io:readln("Email: ").trim();
    string fullName = io:readln("Full name: ").trim();
    string roleChoice = io:readln("Role (1=Customer, 2=Admin): ").trim();
    string phone = io:readln("Phone: ").trim();
    string license = io:readln("License number: ").trim();
    
    if username == "" || email == "" || fullName == "" {
        io:println("Username, email, and full name are required.");
        return;
    }
    
    UserRole role = roleChoice == "2" ? ADMIN : CUSTOMER;
    
    User newUser = {
        user_id: "",
        username: username,
        email: email,
        full_name: fullName,
        role: role,
        phone: phone,
        license_number: license
    };
    
    CreateUserRequest req = {
        admin_token: tokenToUse,
        user: newUser
    };
    
    CreateUserResponse|grpc:Error response = carClient->CreateUser(req);
    
    if response is CreateUserResponse {
        if response.success {
            io:println("Success: " + response.message);
            io:println("User ID: " + response.user_id);
        } else {
            io:println("Failed: " + response.message);
        }
    } else {
        io:println("Error: " + response.message());
    }
}

function listReservations(CarRentalServiceClient carClient, string? token) returns error? {
    string tokenToUse = token ?: "";
    
    io:println("\n=== List Reservations ===");
    string customerFilter = io:readln("Filter by customer ID (optional): ").trim();
    string statusFilter = io:readln("Filter by status (optional): ").trim();
    
    ListReservationsRequest req = {
        admin_token: tokenToUse,
        filter_by_customer: customerFilter,
        filter_by_status: statusFilter
    };
    
    ListReservationsResponse|grpc:Error response = carClient->ListReservations(req);
    
    if response is ListReservationsResponse {
        if response.success {
            io:println("Success: " + response.message);
            foreach Reservation reservation in response.reservations {
                io:println("\n• Reservation ID: " + reservation.reservation_id);
                io:println("  Customer: " + reservation.customer_id);
                io:println("  Car: " + reservation.plate);
                io:println("  Period: " + reservation.start_date + " to " + reservation.end_date);
                io:println("  Status: " + reservation.status.toString());
                io:println("  Total: $" + reservation.total_price.toString());
                io:println("  Created: " + reservation.created_at);
            }
        } else {
            io:println("Failed: " + response.message);
        }
    } else {
        io:println("Error: " + response.message());
    }
}


function printCarDetails(Car car) {
    io:println("\n• " + car.plate + " - " + car.make + " " + car.model + " (" + car.year.toString() + ")");
    io:println("  Status: " + car.status.toString());
    io:println("  Daily price: $" + car.daily_price.toString());
    io:println("  Mileage: " + car.mileage.toString() + " miles");
    io:println("  Location: " + car.location);
    if car.features.length() > 0 {
        io:println("  Features: " + string:'join(", ", ...car.features));
    }
}