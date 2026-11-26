"""Схема ЛР6: python architecture.py (diagrams 0.25.1 и Graphviz)."""

from pathlib import Path
from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2AutoScaling
from diagrams.aws.database import DynamodbTable, RDSPostgresqlInstance
from diagrams.aws.integration import EventbridgeScheduler
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import InternetGateway, Route53, ElbApplicationLoadBalancer
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import S3
from diagrams.onprem.client import Client, User


def main():
    output = Path(__file__).resolve().parent / "imgs" / "architecture"
    output.parent.mkdir(parents=True, exist_ok=True)
    with Diagram(
        "TimeCapsule — архитектура ЛР6",
        filename=str(output), outformat="png", show=False, direction="LR",
        graph_attr={"bgcolor": "#ffffff", "fontname": "DejaVu Sans", "fontsize": "22",
                    "pad": "0.45", "nodesep": "0.7", "ranksep": "1.15",
                    "splines": "polyline", "compound": "true", "dpi": "140"},
        node_attr={"fontname": "DejaVu Sans", "fontsize": "12"},
        edge_attr={"fontname": "DejaVu Sans", "fontsize": "10", "color": "#52677e"},
    ):
        browser = User("Браузер")
        admin = Client("Администратор")
        with Cluster("AWS Cloud · eu-central-1", graph_attr={"bgcolor": "#edf5f7"}):
            s3 = S3("S3 · вложения")
            sessions = DynamodbTable("DynamoDB · сессии\nTTL: expires")
            scheduler = EventbridgeScheduler("Scheduler\n23:00 Europe/Chisinau")
            scheduler_role = IAMRole("Роль Scheduler")
            metrics = Cloudwatch("CloudWatch\nзапросы и тревоги")
            scaling = EC2AutoScaling("Auto Scaling\n2–4 · target 50")
            role = IAMRole("Роль приложения\nS3 и DynamoDB")
            with Cluster("timecapsule-dev-vpc · 10.18.0.0/16", graph_attr={"bgcolor": "#f7f3fb"}):
                igw = InternetGateway("Internet Gateway")
                dns = Route53("Приватный DNS\nCNAME на RDS")
                alb = ElbApplicationLoadBalancer("Application Load Balancer\npublic-a + public-b")
                with Cluster("public-a · eu-central-1a", graph_attr={"bgcolor": "#e9f5e8"}):
                    app_a = EC2("Приложение · nginx / PHP\nASG")
                with Cluster("public-b · eu-central-1b", graph_attr={"bgcolor": "#e9f5e8"}):
                    app_b = EC2("Приложение · nginx / PHP\nASG")
                    bastion = EC2("Bastion")
                with Cluster("Приватные подсети DB subnet group", graph_attr={"bgcolor": "#eaf1fc"}):
                    db = RDSPostgresqlInstance("RDS PostgreSQL\nSingle-AZ · eu-central-1a")
        browser >> igw >> Edge(label="HTTP :80") >> alb
        alb >> Edge(label="HTTP :80 · /health") >> [app_a, app_b]
        admin >> igw >> Edge(label="SSH :22") >> bastion
        bastion >> Edge(label="SSH :22") >> [app_a, app_b]
        for app in (app_a, app_b):
            app >> Edge(label="TLS :5432") >> db
            app >> Edge(label="DNS", style="dashed") >> dns
            app >> Edge(label="HTTPS · сессии") >> sessions
            app >> Edge(label="HTTPS · файлы") >> s3
            app >> Edge(label="роль EC2", style="dashed") >> role
        dns >> Edge(label="CNAME", style="dashed") >> db
        alb >> Edge(label="RequestCountPerTarget", style="dashed") >> metrics
        metrics >> Edge(label="тревоги", style="dashed") >> scaling
        scaling >> Edge(label="управляет", style="dashed") >> [app_a, app_b]
        scheduler >> Edge(label="AssumeRole", style="dashed") >> scheduler_role
        scheduler_role >> Edge(label="StopDBInstance") >> db


if __name__ == "__main__":
    main()
