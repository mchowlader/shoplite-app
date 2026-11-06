import time
import logging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from .config import settings
from .models import Base, Product

logger = logging.getLogger("catalog-api")

# Connect to PostgreSQL using standard SQLAlchemy 2.0 engine
engine_args = {
    "pool_size": 10,
    "max_overflow": 20,
    "pool_pre_ping": True,
}
if "postgresql" in settings.DATABASE_URL:
    engine_args["connect_args"] = {"connect_timeout": 5}

engine = create_engine(settings.DATABASE_URL, **engine_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def init_db(max_retries: int = 5, retry_delay: int = 2) -> bool:
    """
    Creates tables and automatically seeds at least 10 products (Requirement 1.1 & 1.3).
    """
    for attempt in range(1, max_retries + 1):
        try:
            Base.metadata.create_all(bind=engine)
            db: Session = SessionLocal()
            try:
                # Seed exactly 10 initial products if catalog is empty
                if db.query(Product).count() == 0:
                    seed_catalog = [
                        Product(name="Cloud DevOps Handbook", price=49.99, stock=100),
                        Product(name="Production Kubernetes", price=59.99, stock=80),
                        Product(name="Site Reliability Engineering Guide", price=64.99, stock=75),
                        Product(name="Terraform Enterprise Patterns", price=45.00, stock=90),
                        Product(name="AWS Solutions Architect Manual", price=55.00, stock=60),
                        Product(name="Docker Deep Dive & Security", price=39.99, stock=110),
                        Product(name="Linux Administration Bible", price=42.50, stock=85),
                        Product(name="Observability with Prometheus & Grafana", price=48.00, stock=70),
                        Product(name="Chaos Engineering & Resilience", price=52.00, stock=50),
                        Product(name="GitOps with ArgoCD & Flux", price=46.50, stock=95),
                    ]
                    db.add_all(seed_catalog)
                    db.commit()
                    logger.info("Database initialized and 10 products seeded successfully.")
            finally:
                db.close()
            return True
        except Exception as err:
            logger.warning(f"Database connection attempt {attempt}/{max_retries} failed: {err}")
            if attempt < max_retries:
                time.sleep(retry_delay)
            else:
                logger.error("Could not initialize PostgreSQL after maximum retries.")
                return False

