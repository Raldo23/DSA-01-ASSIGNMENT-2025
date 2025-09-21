// how we define our asset data structure
import ballerina/http;

type Component record {
    string name;
    string description;
};

type Schedule record {
    string type;
    string nextDueDate;
};

type Task record {
    string description;
    string status;
};

type WorkOrder record {
    string id;
    string issue;
    string status;
    Task[] tasks;
};

type Asset record {
    string assetTag;
    string name;
    string faculty;
    string department;
    string status;
    string acquiredDate;
    Component[] components;
    Schedule[] schedules;
    WorkOrder[] workOrders;
};
   // In memory database
map<Asset> assetDB = {};

//The above sets up the structure for storing assets, components, schedules, and work orders.

// The following Create the REST API Service

service /assets on new http:Listener(9090) {

    resource function post createAsset(http:Caller caller, http:Request req) returns error? {
        json payload = check req.getJsonPayload();
        Asset asset = check payload.cloneWithType(Asset);
        assetDB[asset.assetTag] = asset;
        check caller->respond({ message: "Asset added successfully" });
    }

    resource function get getAllAssets(http:Caller caller, http:Request req) returns error? {
        check caller->respond(assetDB);
    }

    resource function get getAssetsByFaculty(http:Caller caller, http:Request req) returns error? {
        string faculty = check req.getQueryParam("faculty");
        Asset[] result = [];
        foreach var asset in assetDB.values() {
            if asset.faculty == faculty {
                result.push(asset);
            }
        }
        check caller->respond(result);
    }

    resource function get getOverdueAssets(http:Caller caller, http:Request req) returns error? {
        Asset[] overdue = [];
        foreach var asset in assetDB.values() {
            foreach var schedule in asset.schedules {
                if schedule.nextDueDate < "2025-09-21" {
                    overdue.push(asset);
                    break;
                }
            }
        }
        check caller->respond(overdue);
    }
}
//Use Postman or curl to test the endpoints:

//POST http://localhost:9090/assets → Add asset
//GET http://localhost:9090/assets → View all assets

//GET http://localhost:9090/assets?faculty=Engineering → Filter by faculty

//GET http://localhost:9090/assets/overdue → View overdue assets