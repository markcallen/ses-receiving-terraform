import os
import logging
import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")

BUCKET = os.environ["BUCKET"]
INCOMING_PREFIX = os.environ.get("PREFIX", "incoming/")


def handler(event, context):
    try:
        # Validate event structure
        if "Records" not in event or len(event["Records"]) == 0:
            logger.error("No records found in event")
            return {"ok": False, "error": "No records in event"}

        record = event["Records"][0]["ses"]
        message_id = record["mail"]["messageId"]
        recipients = record["receipt"]["recipients"]

        logger.info(
            f"Processing message {message_id} for {len(recipients)} recipient(s)"
        )

        src_key = f"{INCOMING_PREFIX}{message_id}"
        src = {"Bucket": BUCKET, "Key": src_key}

        # Copy message to each recipient's folder
        for rcpt in recipients:
            folder = rcpt.lower()
            dest_key = f"{folder}/{message_id}.eml"

            try:
                s3.copy_object(Bucket=BUCKET, Key=dest_key, CopySource=src)
                logger.info(f"Copied message to {dest_key}")
            except Exception as e:
                logger.error(f"Failed to copy message to {dest_key}: {str(e)}")
                raise

        # Delete original message
        try:
            s3.delete_object(Bucket=BUCKET, Key=src_key)
            logger.info(f"Deleted original message from {src_key}")
        except Exception as e:
            logger.error(f"Failed to delete original message from {src_key}: {str(e)}")
            raise

        return {"ok": True, "recipients": recipients, "messageId": message_id}

    except KeyError as e:
        logger.error(f"Missing required field in event: {str(e)}")
        return {"ok": False, "error": f"Missing field: {str(e)}"}
    except Exception as e:
        logger.error(f"Unexpected error processing message: {str(e)}")
        return {"ok": False, "error": str(e)}
