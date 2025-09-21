// how we define our asset data structure

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

// In-memory database
map<Asset> assetDB = {};

//The above sets up the structure for storing assets, components, schedules, and work orders.

// The following Create the REST API Service

import ballerina/http;

service /assets on new http:Listener(9090) {

    resource function post createAsset(http:Caller caller, http:Request req) returns error? {
        Asset asset = check req.getJsonPayload();
        assetDB[asset.assetTag] = asset;
        check caller->respond("Asset added successfully");
    }

    resource function get getAllAssets(http:Caller caller, http:Request req) returns error? {
        check caller->respond(assetDB);
    }
}

//*The above gives us:

//  POST /assets → to add a new asset

//  GET /assets → to view all assets*/
