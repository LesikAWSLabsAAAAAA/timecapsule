"""Схема лабораторной работы: python architecture.py (нужны diagrams и Graphviz)."""

from pathlib import Path

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.network import InternetGateway, NATGateway, Route53
from diagrams.generic.blank import Blank
from diagrams.onprem.client import Client, User
from diagrams.onprem.vcs import Github


output = Path(__file__).resolve().parent / "imgs" / "architecture"
graph = {
    "bgcolor": "#ffffff",
    "fontname": "DejaVu Sans",
    "fontsize": "22",
    "pad": "0.5",
    "nodesep": "0.65",
    "ranksep": "1.0",
    "splines": "polyline",
    "compound": "true",
    "dpi": "150",
}
node = {"fontname": "DejaVu Sans", "fontsize": "12"}
edge = {"fontname": "DejaVu Sans", "fontsize": "10", "color": "#52677e"}

with Diagram(
    "TimeCapsule — лабораторная работа №3",
    filename=str(output),
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph,
    node_attr=node,
    edge_attr=edge,
):
    user = User("Пользователь")
    admin = Client("Компьютер\nадминистратора")
    github = Github("GitHub\nTimeCapsule")

    with Cluster("AWS Cloud", graph_attr={"bgcolor": "#f4f6f9", "color": "#8a97a6"}):
        with Cluster("Регион eu-central-1 (Frankfurt)", graph_attr={"bgcolor": "#edf5f7", "color": "#3d9ba8"}):
            with Cluster("timecapsule-dev-vpc · 10.18.0.0/16", graph_attr={"bgcolor": "#f7f3fb", "color": "#9163b2"}):
                igw = InternetGateway("timecapsule-dev-igw\nInternet Gateway")
                dns = Route53("Приватная зона Route 53\ntimecapsule.internal\ndb → 10.18.11.157")

                with Cluster("Зона eu-central-1a", graph_attr={"bgcolor": "#ffffff", "color": "#a0aab7"}):
                    with Cluster("timecapsule-dev-public-a · 10.18.0.0/24", graph_attr={"bgcolor": "#e9f5e8", "color": "#6eac71"}):
                        app = EC2("timecapsule-dev-app\nweb-sg · Elastic IP\nnginx / PHP / TimeCapsule")
                        nat = NATGateway("timecapsule-dev-nat-a\nвременный NAT Gateway")
                    with Cluster("timecapsule-dev-private-a · 10.18.10.0/24", graph_attr={"bgcolor": "#eaf1fc", "color": "#7b9ac4"}):
                        spare = Blank("Резервная подсеть")

                with Cluster("Зона eu-central-1b", graph_attr={"bgcolor": "#ffffff", "color": "#a0aab7"}):
                    with Cluster("timecapsule-dev-public-b · 10.18.1.0/24", graph_attr={"bgcolor": "#e9f5e8", "color": "#6eac71"}):
                        bastion = EC2("timecapsule-dev-bastion\nbastion-sg · SSH")
                    with Cluster("timecapsule-dev-private-b · 10.18.11.0/24", graph_attr={"bgcolor": "#eaf1fc", "color": "#7b9ac4"}):
                        db = EC2("timecapsule-dev-db\ndb-sg · PostgreSQL :5432\n10.18.11.157")

    admin >> Edge(label="git push") >> github
    github >> Edge(label="git pull / HTTPS", constraint="false") >> app
    user >> Edge(label="HTTP :80") >> igw
    admin >> Edge(label="SSH :22, мой IP") >> igw
    igw >> Edge(label="HTTP :80") >> app
    igw >> Edge(label="SSH :22") >> bastion
    bastion >> Edge(label="SSH :22", constraint="false") >> app
    bastion >> Edge(label="SSH :22") >> db
    app >> Edge(label="PostgreSQL :5432") >> db
    app >> Edge(label="DNS", style="dashed", constraint="false") >> dns
    db >> Edge(label="обновления", style="dashed", color="#c77b24", constraint="false") >> nat
    nat >> Edge(label="временно", style="dashed", color="#c77b24", constraint="false") >> igw
