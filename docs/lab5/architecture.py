"""Схема ЛР5: python architecture.py (diagrams 0.25.1 и Graphviz)."""

from pathlib import Path

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.integration import EventbridgeScheduler
from diagrams.aws.network import InternetGateway, Route53
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import S3
from diagrams.onprem.client import Client, User


def main() -> None:
    output = Path(__file__).resolve().parent / "imgs" / "architecture"
    output.parent.mkdir(parents=True, exist_ok=True)

    with Diagram(
        "TimeCapsule — архитектура после ЛР5",
        filename=str(output),
        outformat="png",
        show=False,
        direction="LR",
        graph_attr={
            "bgcolor": "#ffffff",
            "fontname": "DejaVu Sans",
            "fontsize": "22",
            "pad": "0.45",
            "nodesep": "0.7",
            "ranksep": "1.15",
            "splines": "polyline",
            "compound": "true",
            "dpi": "140",
        },
        node_attr={"fontname": "DejaVu Sans", "fontsize": "12"},
        edge_attr={"fontname": "DejaVu Sans", "fontsize": "10", "color": "#52677e"},
    ):
        browser = User("Браузер")
        admin = Client("Администратор")

        with Cluster("AWS Cloud · eu-central-1", graph_attr={"bgcolor": "#edf5f7"}):
            s3 = S3("S3 · вложения\nБраузер: GET по подписанному URL")
            scheduler = EventbridgeScheduler("EventBridge Scheduler\n23:00 Europe/Chisinau")
            scheduler_role = IAMRole("Роль Scheduler\nStopDBInstance только для этой БД")

            with Cluster("timecapsule-dev-vpc · 10.18.0.0/16", graph_attr={"bgcolor": "#f7f3fb"}):
                igw = InternetGateway("Internet Gateway")
                dns = Route53("Приватная зона Route 53\ndb.timecapsule.internal → CNAME RDS")
                public = {"bgcolor": "#e9f5e8", "color": "#6eac71"}
                private = {"bgcolor": "#eaf1fc", "color": "#7b9ac4"}

                with Cluster("public-a · eu-central-1a", graph_attr=public):
                    app = EC2("timecapsule-dev-app\nnginx / PHP · web-sg")
                with Cluster("public-b · eu-central-1b", graph_attr=public):
                    bastion = EC2("timecapsule-dev-bastion\nbastion-sg")

                with Cluster("Приватные подсети DB subnet group", graph_attr={"bgcolor": "#f3f7fc"}):
                    with Cluster("private-a · eu-central-1a", graph_attr=private):
                        db = RDSPostgresqlInstance(
                            "timecapsule-dev-rds\nPostgreSQL 16 · Single-AZ\nбез публичного доступа"
                        )
                    with Cluster("private-b · eu-central-1b", graph_attr=private):
                        EC2("timecapsule-dev-db\nостановлен, диск сохранён")

        browser >> igw >> Edge(label="HTTP :80") >> app
        admin >> igw >> Edge(label="SSH :22") >> bastion
        bastion >> Edge(label="SSH :22") >> app
        app >> Edge(label="DNS", style="dashed") >> dns
        dns >> Edge(label="CNAME", style="dashed") >> db
        app >> Edge(label="TLS :5432 · только web-sg", color="#2460aa") >> db
        app >> Edge(label="HTTPS · роль EC2", color="#995122") >> s3
        scheduler >> Edge(label="AssumeRole", style="dashed") >> scheduler_role
        scheduler_role >> Edge(label="StopDBInstance · AWS API", color="#a24e6e") >> db


if __name__ == "__main__":
    main()
