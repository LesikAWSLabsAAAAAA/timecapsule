"""Схема индивидуальной работы: python architecture.py (diagrams 0.25.1 и Graphviz)."""

from pathlib import Path

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, Lambda
from diagrams.aws.database import DynamodbTable, RDSPostgresqlInstance
from diagrams.aws.integration import (
    EventbridgeScheduler,
    SimpleNotificationServiceSns,
    SimpleQueueServiceSqs,
)
from diagrams.aws.network import ElbApplicationLoadBalancer
from diagrams.aws.security import IAMRole, SecretsManager
from diagrams.aws.storage import S3
from diagrams.onprem.client import Client, User


def main() -> None:
    output = Path(__file__).resolve().parent / "imgs" / "architecture"
    output.parent.mkdir(parents=True, exist_ok=True)

    with Diagram(
        "TimeCapsule — архитектура индивидуальной работы · Secrets Manager",
        filename=str(output),
        outformat="png",
        show=False,
        direction="LR",
        graph_attr={
            "bgcolor": "#ffffff",
            "fontname": "DejaVu Sans",
            "fontsize": "22",
            "pad": "0.45",
            "nodesep": "0.50",
            "ranksep": "0.85",
            "splines": "polyline",
            "compound": "true",
            "dpi": "140",
        },
        node_attr={"fontname": "DejaVu Sans", "fontsize": "11"},
        edge_attr={"fontname": "DejaVu Sans", "fontsize": "10", "color": "#52677e"},
    ):
        user = User("Пользователь")
        admin = Client("Администратор")
        email = User("Почта\nполучатель")

        with Cluster("AWS Cloud · eu-central-1", graph_attr={"bgcolor": "#edf5f7"}):
            secret = SecretsManager("Secrets Manager\ntimecapsule-dev-db")
            role = IAMRole("Роль EC2\ntimecapsule-dev-app-role")
            bucket = S3("S3 · вложения")
            sessions = DynamodbTable("DynamoDB · сессии с TTL")
            events = SimpleNotificationServiceSns("SNS\ntimecapsule-dev-events")
            queue = SimpleQueueServiceSqs("SQS\ntimecapsule-dev-mail")
            schedule = EventbridgeScheduler("EventBridge Scheduler\nраз в минуту")

            with Cluster("VPC · 10.18.0.0/16", graph_attr={"bgcolor": "#f7f3fb"}):
                with Cluster("Публичные подсети", graph_attr={"bgcolor": "#e9f5e8"}):
                    alb = ElbApplicationLoadBalancer("ALB")
                    app = EC2("EC2 · ASG 2–4\nnginx / PHP\nКэш пароля: tmpfs · 300 с")
                    bastion = EC2("Bastion")
                with Cluster("Приватные подсети", graph_attr={"bgcolor": "#eaf1fc"}):
                    db = RDSPostgresqlInstance("RDS PostgreSQL 16\nSingle-AZ")
                    mailer = Lambda("Lambda mailer")
                    opener = Lambda("Lambda opener")

        user >> Edge(label="HTTP :80") >> alb
        alb >> Edge(label="HTTP :80 · /health", weight="8") >> app
        admin >> Edge(label="SSH :22") >> bastion >> app

        secret_flow = {"color": "#9b6700", "fontcolor": "#775000", "penwidth": "2.0"}
        app >> Edge(label="GetSecretValue\n(DB_SECRET_ARN из env)", **secret_flow) >> secret
        # Оба ребра идут в одном направлении для dot, но стрелка ответа развёрнута.
        app - Edge(label="пароль БД", reverse=True, **secret_flow) - secret
        app >> Edge(label="TLS :5432", weight="8", color="#2460aa", penwidth="2.0") >> db
        role >> Edge(label="роль инстанса", style="dashed", constraint="false") >> app
        role >> Edge(
            label="timecapsule-dev-app-secretsmanager\nGetSecretValue только для этого секрета",
            style="dashed",
        ) >> secret

        app >> bucket
        app >> Edge(minlen="2") >> sessions
        app >> Edge(label="capsule.sealed") >> events
        events >> Edge(label="фильтр sealed") >> queue
        mailer - Edge(reverse=True, constraint="false") - queue
        db << mailer
        opener - Edge(label="вызов", reverse=True) - schedule
        db << opener
        opener >> Edge(label="при успехе", style="dashed", constraint="false") >> events
        events >> Edge(label="подписка\ncapsules.opened") >> email


if __name__ == "__main__":
    main()
