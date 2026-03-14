"""
seed_dynamodb.py
Seeds the smartcx-orders DynamoDB table with 20+ mock orders covering all statuses.

Usage:
    python seed_dynamodb.py --table smartcx-demo-orders --region us-east-1
"""
import argparse
import boto3
from decimal import Decimal


ORDERS = [
    {
        "orderId": "ORD-10001",
        "customerId": "CUST-001",
        "customerName": "Jane Smith",
        "customerPhone": "+16165550101",
        "status": "SHIPPED",
        "items": [{"name": "Wireless Headphones", "qty": 1, "price": Decimal("79.99")}],
        "trackingNumber": "1Z999AA10123456701",
        "carrier": "UPS",
        "estimatedDelivery": "2025-03-18",
        "orderDate": "2025-03-12",
        "totalAmount": Decimal("79.99"),
    },
    {
        "orderId": "ORD-10002",
        "customerId": "CUST-002",
        "customerName": "Michael Johnson",
        "customerPhone": "+16165550102",
        "status": "DELIVERED",
        "items": [{"name": "Bluetooth Speaker", "qty": 1, "price": Decimal("49.99")}],
        "trackingNumber": "1Z999AA10123456702",
        "carrier": "UPS",
        "estimatedDelivery": "2025-03-10",
        "orderDate": "2025-03-07",
        "totalAmount": Decimal("49.99"),
    },
    {
        "orderId": "ORD-10003",
        "customerId": "CUST-003",
        "customerName": "Sarah Williams",
        "customerPhone": "+16165550103",
        "status": "PROCESSING",
        "items": [
            {"name": "USB-C Hub", "qty": 1, "price": Decimal("39.99")},
            {"name": "Laptop Stand", "qty": 1, "price": Decimal("29.99")},
        ],
        "trackingNumber": "",
        "carrier": "",
        "estimatedDelivery": "2025-03-20",
        "orderDate": "2025-03-13",
        "totalAmount": Decimal("69.98"),
    },
    {
        "orderId": "ORD-10004",
        "customerId": "CUST-004",
        "customerName": "Robert Davis",
        "customerPhone": "+16165550104",
        "status": "CANCELLED",
        "items": [{"name": "Mechanical Keyboard", "qty": 1, "price": Decimal("129.99")}],
        "trackingNumber": "",
        "carrier": "",
        "estimatedDelivery": "",
        "orderDate": "2025-03-08",
        "totalAmount": Decimal("129.99"),
    },
    {
        "orderId": "ORD-10005",
        "customerId": "CUST-005",
        "customerName": "Emily Brown",
        "customerPhone": "+16165550105",
        "status": "RETURN_REQUESTED",
        "items": [{"name": "Gaming Mouse", "qty": 1, "price": Decimal("59.99")}],
        "trackingNumber": "1Z999AA10123456705",
        "carrier": "FedEx",
        "estimatedDelivery": "2025-03-05",
        "orderDate": "2025-03-01",
        "totalAmount": Decimal("59.99"),
    },
    {
        "orderId": "ORD-10006",
        "customerId": "CUST-006",
        "customerName": "David Wilson",
        "customerPhone": "+16165550106",
        "status": "SHIPPED",
        "items": [{"name": "4K Webcam", "qty": 1, "price": Decimal("99.99")}],
        "trackingNumber": "9400111899223456706",
        "carrier": "USPS",
        "estimatedDelivery": "2025-03-19",
        "orderDate": "2025-03-14",
        "totalAmount": Decimal("99.99"),
    },
    {
        "orderId": "ORD-10007",
        "customerId": "CUST-007",
        "customerName": "Jessica Martinez",
        "customerPhone": "+16165550107",
        "status": "DELIVERED",
        "items": [
            {"name": "Smart Watch", "qty": 1, "price": Decimal("199.99")},
            {"name": "Watch Band", "qty": 2, "price": Decimal("14.99")},
        ],
        "trackingNumber": "1Z999AA10123456707",
        "carrier": "UPS",
        "estimatedDelivery": "2025-03-09",
        "orderDate": "2025-03-04",
        "totalAmount": Decimal("229.97"),
    },
    {
        "orderId": "ORD-10008",
        "customerId": "CUST-008",
        "customerName": "James Anderson",
        "customerPhone": "+16165550108",
        "status": "PROCESSING",
        "items": [{"name": "Noise Cancelling Earbuds", "qty": 1, "price": Decimal("149.99")}],
        "trackingNumber": "",
        "carrier": "",
        "estimatedDelivery": "2025-03-21",
        "orderDate": "2025-03-14",
        "totalAmount": Decimal("149.99"),
    },
    {
        "orderId": "ORD-10009",
        "customerId": "CUST-009",
        "customerName": "Ashley Taylor",
        "customerPhone": "+16165550109",
        "status": "SHIPPED",
        "items": [{"name": "Portable Charger", "qty": 2, "price": Decimal("29.99")}],
        "trackingNumber": "396501234567890009",
        "carrier": "FedEx",
        "estimatedDelivery": "2025-03-17",
        "orderDate": "2025-03-11",
        "totalAmount": Decimal("59.98"),
    },
    {
        "orderId": "ORD-10010",
        "customerId": "CUST-010",
        "customerName": "Christopher Thomas",
        "customerPhone": "+16165550110",
        "status": "RETURN_REQUESTED",
        "items": [{"name": "Monitor Arm", "qty": 1, "price": Decimal("79.99")}],
        "trackingNumber": "1Z999AA10123456710",
        "carrier": "UPS",
        "estimatedDelivery": "2025-03-03",
        "orderDate": "2025-02-27",
        "totalAmount": Decimal("79.99"),
    },
    {
        "orderId": "ORD-10011",
        "customerId": "CUST-011",
        "customerName": "Amanda Jackson",
        "customerPhone": "+16165550111",
        "status": "DELIVERED",
        "items": [{"name": "LED Desk Lamp", "qty": 1, "price": Decimal("34.99")}],
        "trackingNumber": "1Z999AA10123456711",
        "carrier": "UPS",
        "estimatedDelivery": "2025-03-06",
        "orderDate": "2025-03-02",
        "totalAmount": Decimal("34.99"),
    },
    {
        "orderId": "ORD-10012",
        "customerId": "CUST-012",
        "customerName": "Matthew White",
        "customerPhone": "+16165550112",
        "status": "CANCELLED",
        "items": [{"name": "External SSD 1TB", "qty": 1, "price": Decimal("109.99")}],
        "trackingNumber": "",
        "carrier": "",
        "estimatedDelivery": "",
        "orderDate": "2025-03-10",
        "totalAmount": Decimal("109.99"),
    },
    {
        "orderId": "ORD-10013",
        "customerId": "CUST-013",
        "customerName": "Stephanie Harris",
        "customerPhone": "+16165550113",
        "status": "SHIPPED",
        "items": [
            {"name": "Ergonomic Chair Cushion", "qty": 1, "price": Decimal("44.99")},
            {"name": "Wrist Rest Pad", "qty": 1, "price": Decimal("19.99")},
        ],
        "trackingNumber": "9400111899223456713",
        "carrier": "USPS",
        "estimatedDelivery": "2025-03-18",
        "orderDate": "2025-03-13",
        "totalAmount": Decimal("64.98"),
    },
    {
        "orderId": "ORD-10014",
        "customerId": "CUST-014",
        "customerName": "Daniel Martin",
        "customerPhone": "+16165550114",
        "status": "PROCESSING",
        "items": [{"name": "VR Headset", "qty": 1, "price": Decimal("299.99")}],
        "trackingNumber": "",
        "carrier": "",
        "estimatedDelivery": "2025-03-22",
        "orderDate": "2025-03-14",
        "totalAmount": Decimal("299.99"),
    },
    {
        "orderId": "ORD-10015",
        "customerId": "CUST-015",
        "customerName": "Nicole Garcia",
        "customerPhone": "+16165550115",
        "status": "DELIVERED",
        "items": [{"name": "Phone Stand", "qty": 3, "price": Decimal("12.99")}],
        "trackingNumber": "1Z999AA10123456715",
        "carrier": "UPS",
        "estimatedDelivery": "2025-03-08",
        "orderDate": "2025-03-03",
        "totalAmount": Decimal("38.97"),
    },
    {
        "orderId": "ORD-10016",
        "customerId": "CUST-016",
        "customerName": "Kevin Robinson",
        "customerPhone": "+16165550116",
        "status": "RETURN_REQUESTED",
        "items": [{"name": "Smart Home Hub", "qty": 1, "price": Decimal("89.99")}],
        "trackingNumber": "396501234567890016",
        "carrier": "FedEx",
        "estimatedDelivery": "2025-03-01",
        "orderDate": "2025-02-24",
        "totalAmount": Decimal("89.99"),
    },
    {
        "orderId": "ORD-10017",
        "customerId": "CUST-017",
        "customerName": "Rachel Clark",
        "customerPhone": "+16165550117",
        "status": "SHIPPED",
        "items": [{"name": "Drawing Tablet", "qty": 1, "price": Decimal("179.99")}],
        "trackingNumber": "1Z999AA10123456717",
        "carrier": "UPS",
        "estimatedDelivery": "2025-03-20",
        "orderDate": "2025-03-14",
        "totalAmount": Decimal("179.99"),
    },
    {
        "orderId": "ORD-10018",
        "customerId": "CUST-018",
        "customerName": "Brandon Lewis",
        "customerPhone": "+16165550118",
        "status": "DELIVERED",
        "items": [
            {"name": "HDMI Cable 6ft", "qty": 2, "price": Decimal("9.99")},
            {"name": "DisplayPort Cable", "qty": 1, "price": Decimal("12.99")},
        ],
        "trackingNumber": "9400111899223456718",
        "carrier": "USPS",
        "estimatedDelivery": "2025-03-07",
        "orderDate": "2025-03-03",
        "totalAmount": Decimal("32.97"),
    },
    {
        "orderId": "ORD-10019",
        "customerId": "CUST-019",
        "customerName": "Megan Lee",
        "customerPhone": "+16165550119",
        "status": "CANCELLED",
        "items": [{"name": "Streaming Microphone", "qty": 1, "price": Decimal("139.99")}],
        "trackingNumber": "",
        "carrier": "",
        "estimatedDelivery": "",
        "orderDate": "2025-03-09",
        "totalAmount": Decimal("139.99"),
    },
    {
        "orderId": "ORD-10020",
        "customerId": "CUST-020",
        "customerName": "Tyler Walker",
        "customerPhone": "+16165550120",
        "status": "PROCESSING",
        "items": [{"name": "Mechanical Numpad", "qty": 1, "price": Decimal("54.99")}],
        "trackingNumber": "",
        "carrier": "",
        "estimatedDelivery": "2025-03-23",
        "orderDate": "2025-03-14",
        "totalAmount": Decimal("54.99"),
    },
    # Two extra entries to bump above 20 and provide ANI-lookup test numbers
    {
        "orderId": "ORD-10042",
        "customerId": "CUST-882",
        "customerName": "Jane Smith",
        "customerPhone": "+16165550192",
        "status": "SHIPPED",
        "items": [{"name": "Wireless Headphones", "qty": 1, "price": Decimal("79.99")}],
        "trackingNumber": "1Z999AA10123456784",
        "carrier": "UPS",
        "estimatedDelivery": "2025-03-18",
        "orderDate": "2025-03-12",
        "totalAmount": Decimal("79.99"),
    },
    {
        "orderId": "ORD-10099",
        "customerId": "CUST-099",
        "customerName": "Demo Tester",
        "customerPhone": "+16165550199",
        "status": "SHIPPED",
        "items": [{"name": "Test Item", "qty": 1, "price": Decimal("9.99")}],
        "trackingNumber": "1Z999AA10123456799",
        "carrier": "UPS",
        "estimatedDelivery": "2025-03-19",
        "orderDate": "2025-03-13",
        "totalAmount": Decimal("9.99"),
    },
]

STATUS_COUNTS = {}
for o in ORDERS:
    STATUS_COUNTS[o["status"]] = STATUS_COUNTS.get(o["status"], 0) + 1


def main():
    parser = argparse.ArgumentParser(description="Seed SmartCX demo orders table")
    parser.add_argument("--table",  required=True, help="DynamoDB table name")
    parser.add_argument("--region", default="us-east-1", help="AWS region")
    args = parser.parse_args()

    dynamodb = boto3.resource("dynamodb", region_name=args.region)
    table = dynamodb.Table(args.table)

    print(f"Seeding {len(ORDERS)} orders into {args.table} ({args.region})...\n")

    success = 0
    failures = []
    with table.batch_writer() as batch:
        for order in ORDERS:
            try:
                batch.put_item(Item=order)
                success += 1
            except Exception as e:
                failures.append((order["orderId"], str(e)))

    # Summary table
    col_w = 20
    print(f"{'Order ID':<14} {'Customer':<22} {'Status':<20} {'Total':>8}")
    print("-" * 68)
    for o in ORDERS:
        print(f"{o['orderId']:<14} {o['customerName']:<22} {o['status']:<20} ${o['totalAmount']:>7.2f}")

    print()
    print(f"Seeded {success}/{len(ORDERS)} orders successfully.")
    if failures:
        print(f"\nFailed ({len(failures)}):")
        for order_id, err in failures:
            print(f"  {order_id}: {err}")

    print("\nStatus breakdown:")
    for status, count in sorted(STATUS_COUNTS.items()):
        print(f"  {status:<20} {count}")


if __name__ == "__main__":
    main()
