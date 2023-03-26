# Setup
from web3 import Web3
import json

alchemy_url = "https://opt-goerli.g.alchemy.com/v2/4ugTGoOUry6knOzLrsTtKSmnW7-P3NMA"
w3 = Web3(Web3.HTTPProvider(alchemy_url))

# Print if web3 is successfully connected
print(w3.isConnected())

# Get the latest block number
latest_block = w3.eth.block_number
print(latest_block)

# Get the balance of an account
balance = w3.eth.get_balance('0x5B8069d77658aC2817CB922c0B9454ee3c1377b6')
print(balance)

# Load the ABI from the file
with open("surveywei.abi", "r") as f:
    contract_abi = json.load(f)

contract_address = "0x12feB242DF388c4397EC8B1650F4A09C5C1f6542"

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

# ... (previous code)

# Get logs for all event topics
from_block = 7147916  # Replace with the block number you want to start with
to_block = 7147943

all_events = []

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
            decoded_log = contract.events[event_name]().processLog(log)
            all_events.append({"args": decoded_log["args"], "event": decoded_log["event"]})
            #print(f"{event_name} log: {decoded_log}")
            #print(decoded_log)
        else:
            print(f"ABI entry for {event_name} not found")

#print(all_events)
for i in all_events:
    if i["event"] == "SurveyStarted":
        print(i["args"]["id"])
        print(i["args"]["respondent"])
        print(i)

