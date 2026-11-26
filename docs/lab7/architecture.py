"""Схема ЛР7 на основе architecture.py из ЛР6."""
from pathlib import Path
from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2AutoScaling, Lambda
from diagrams.aws.database import DynamodbTable, RDSPostgresqlInstance
from diagrams.aws.integration import EventbridgeScheduler, SimpleNotificationServiceSns, SimpleQueueServiceSqs
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import ElbApplicationLoadBalancer, InternetGateway, Route53
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import S3
from diagrams.onprem.client import Client, User


def main():
    path = Path(__file__).resolve().parent / "imgs" / "architecture"
    path.parent.mkdir(parents=True, exist_ok=True)
    with Diagram(
        "TimeCapsule — архитектура ЛР7", filename=str(path), show=False,
        direction="LR", outformat="png",
        graph_attr={"bgcolor": "#ffffff", "fontname": "DejaVu Sans",
                    "fontsize": "22", "pad": "0.45", "ranksep": "1.0",
                    "nodesep": "0.65", "splines": "polyline", "dpi": "140"},
        node_attr={"fontname": "DejaVu Sans", "fontsize": "11"},
        edge_attr={"fontname": "DejaVu Sans", "fontsize": "10", "color": "#52677e"},
    ):
        user = User("Пользователь")
        admin = Client("Администратор")
        email = User("Почта\nоткрытые капсулы")
        with Cluster("AWS Cloud · eu-central-1", graph_attr={"bgcolor": "#edf5f7"}):
            bucket = S3("Вложения")
            sessions = DynamodbTable("Сессии · TTL")
            events = SimpleNotificationServiceSns("timecapsule-dev-events")
            queue = SimpleQueueServiceSqs("timecapsule-dev-mail")
            dlq = SimpleQueueServiceSqs("timecapsule-dev-mail-dlq")
            schedule = EventbridgeScheduler("Открытие · раз в минуту")
            dbstop = EventbridgeScheduler("Остановка RDS · ЛР5")
            logs = Cloudwatch("Журналы и метрики")
            role = IAMRole("Роли EC2 и Lambda")
            with Cluster("VPC · 10.18.0.0/16", graph_attr={"bgcolor": "#f7f3fb"}):
                igw = InternetGateway("Internet Gateway")
                dns = Route53("Приватный DNS")
                with Cluster("Публичные подсети", graph_attr={"bgcolor": "#e9f5e8"}):
                    app = EC2("timecapsule-dev-app\nElastic IP · nginx/PHP")
                    bastion = EC2("Bastion")
                    alb = ElbApplicationLoadBalancer("ALB · ЛР6\nотключён")
                    asg = EC2AutoScaling("ASG · ЛР6\nотключена")
                with Cluster("Приватные подсети", graph_attr={"bgcolor": "#eaf1fc"}):
                    mailer = Lambda("Mailer")
                    opener = Lambda("Opener")
                    db = RDSPostgresqlInstance("RDS PostgreSQL")
        user >> igw >> Edge(label="HTTP") >> app
        admin >> igw >> Edge(label="SSH") >> bastion >> Edge(label="SSH") >> app
        app >> Edge(label="файлы") >> bucket
        app >> Edge(label="сессии") >> sessions
        app >> Edge(label="TLS :5432") >> db
        app >> Edge(label="DNS", style="dashed") >> dns >> Edge(style="dashed") >> db
        app >> Edge(label="capsule.sealed") >> events
        events >> Edge(label="фильтр sealed") >> queue >> mailer
        queue >> Edge(label="ошибки / redrive", style="dashed") >> dlq
        mailer >> Edge(label="уведомления") >> db
        schedule >> Edge(label="async") >> opener
        opener >> Edge(label="открытие + уведомление") >> db
        opener >> Edge(label="success destination", style="dashed") >> events
        events >> Edge(label="фильтр opened") >> email
        mailer >> logs
        opener >> logs
        dbstop >> Edge(label="stop") >> db
        role >> Edge(label="IAM", style="dashed") >> app
        alb >> Edge(label="при запуске ЛР6", style="dashed") >> asg


if __name__ == "__main__":
    main()
