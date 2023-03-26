# Setup
import time
import boto3
from botocore.exceptions import ClientError
from web3 import Web3
import json
import firebase_admin
from firebase_admin import credentials, db


alchemy_url= "https://opt-mainnet.g.alchemy.com/v2/Qx_Z44GMAHKxaF_XYc2TQkhqNHpON-9q"
#alchemy_url= "https://opt-goerli.g.alchemy.com/v2/4ugTGoOUry6knOzLrsTtKSmnW7-P3NMA"
w3 = Web3(Web3.HTTPProvider(alchemy_url))

dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
table_name = "surveywei"
partition_key_name = "last_block"
partition_key_value = 1

cred = credentials.Certificate("surveywei-1b1e0-firebase-adminsdk-tty9i-ed79c7c569.json")

firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://surveywei-1b1e0-default-rtdb.firebaseio.com/'
 })



# Print if web3 is successfully connected
print(w3.is_connected())

# Get the latest block number
latest_block = w3.eth.block_number
print(latest_block)

# Get the balance of an account
balance = w3.eth.get_balance('0x5B8069d77658aC2817CB922c0B9454ee3c1377b6')
print(balance)

# Load the ABI from the file
with open("surveywei.abi", "r") as f:
    contract_abi = json.load(f)

contract_address = "0xd3f2E5e4891E8F779533f95DA7A5AB075F9afd86"
#contract_address = "0x12feB242DF388c4397EC8B1650F4A09C5C1f6542"

# Create a contract instance
contract = w3.eth.contract(address=contract_address, abi=contract_abi)

# Event signatures
event_signatures = {
    "AttestationSubmitted": "0x5e402e2ae7392007c31b3dd61a4db6358323df6cc737e17920c5a557d41132e3",
    "SurveyClosed": "0xcbafb27f888c184aaa85fe02a8c3fa4c4e56d562f1a740d959fc80c1fa5529ef",
    "SurveyCompleted": "0x3df5e88856c51d0c8170efd52d7d8e4b8d982411cd92c2486160c5d172008f80",
    "SurveyCreated": "0x53a595437b9405acb5413690ea8277715ea0822a36578644a5f3857ea77e1c69",
    "SurveyStarted": "0x3affd8a53829acbfcc9e56d36b972dbca356b26529ffe2d9e0999505b43099e0",
    "TransferSuccessful": "0xc05aa721a8d88be57c93f6d0d3c44b71dda42835b8dd02592dd1d38fd7e63eaa"
}


def get_last_block_number():
    try:
        response = dynamodb.Table(table_name).get_item(Key={partition_key_name: partition_key_value})
    except ClientError as e:
        print(e.response["Error"]["Message"])
    else:
        return response["Item"]["blockstamp"]

def update_last_block_number(block_number):
    try:
        response = dynamodb.Table(table_name).update_item(
            Key={partition_key_name: partition_key_value},
            UpdateExpression="set blockstamp=:b",
            ExpressionAttributeValues={":b": block_number},
            ReturnValues="UPDATED_NEW"
        )
    except ClientError as e:
        print(e.response["Error"]["Message"])

def updateSurvey(_id):

    root_ref = db.reference()
    surveys_ref = root_ref.child('surveys')
    surveys_data = surveys_ref.get()

    for i in surveys_data:
        if i == _id:
            child1_ref = surveys_ref.child(i)
            child1_data = child1_ref.get()
            for k in child1_data:
                child1_data[k]['created'] = True
                child1_ref.update(child1_data)

def updateResponse(_id, _respondent, _status):

    root_ref = db.reference()
    response_ref = root_ref.child('responses')
    response_data = response_ref.get()

    for i in response_data:
        for k in response_data[i]:
            child1_ref = response_ref.child(i)
            child1_data = child1_ref.get()
            creator = response_data[i][k]["creator"]
            surveyId = response_data[i][k]["firebaseID"]

            if creator == _respondent and surveyId == _id:

                if _status == 0:
                    child1_data[k]['started'] = True
                    child1_ref.update(child1_data)
                    return
                elif _status == 1:
                    child1_data[k]['completed'] = True
                    child1_ref.update(child1_data)
                    return

while True:
    all_events = []
    from_block =int(get_last_block_number())
    to_block = w3.eth.block_number

    print(from_block)
    print(to_block)

    if to_block - from_block > 100:
        to_block = from_block + 100

    print(to_block)

    for event_name, event_signature in event_signatures.items():
        event_filter = w3.eth.filter({
            "fromBlock": from_block,
            "toBlock": to_block,
            "address": contract_address,
            "topics": [event_signature]
        })

        logs = w3.eth.get_filter_logs(event_filter.filter_id)

        # Loop through logs and decode the data

        for log in logs:
            # Find the ABI entry for the current event
            event_abi = None
            for entry in contract_abi:
                if entry["type"] == "event" and entry["name"] == event_name:
                    event_abi = entry
                    break

        # Decode the log with the ABI entry
            if event_abi is not None:
                decoded_log = contract.events[event_name]().process_log(log)
                all_events.append({"args": decoded_log["args"], "event": decoded_log["event"]})
                #print(f"{event_name} log: {decoded_log}")
                #print(decoded_log)
            else:
                print(f"ABI entry for {event_name} not found")

    #print(all_events)
    for i in all_events:
        print(i)
        if i["event"] == "SurveyCreated":
            updateSurvey(i["args"]["id"])
        elif i["event"] == "SurveyStarted":
            updateResponse(i["args"]["id"], i["args"]["respondent"],0)
        elif i["event"] == "SurveyCompleted":
            updateResponse(i["args"]["id"], i["args"]["respondent"],1)

    update_last_block_number(to_block)
    time.sleep(20)

                             