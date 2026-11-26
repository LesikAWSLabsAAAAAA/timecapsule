import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    for record in event["Records"]:
        review = json.loads(record["body"])
        logger.info("%s: %s/5 %s", review["id"], review["rating"], (review.get("text") or "")[:20])
