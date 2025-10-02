#!/usr/bin/env python3
"""
Cloud-Native Web Service with Database Integration
A scalable REST API demonstrating cloud-native patterns
"""

import os
import time
import logging
from datetime import datetime
from typing import List, Optional

import psycopg2
from psycopg2.extras import RealDictCursor
from flask import Flask, request, jsonify, g
from werkzeug.exceptions import BadRequest, NotFound
import prometheus_client
from prometheus_client import Counter, Histogram, Gauge

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration')
ACTIVE_CONNECTIONS = Gauge('database_connections_active', 'Active database connections')

app = Flask(__name__)

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': os.getenv('DB_PORT', '5432'),
    'database': os.getenv('DB_NAME', 'cloudapp'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', 'password')
}


class DatabaseManager:
    """Database connection and operations manager"""
    
    def __init__(self):
        self.connection_pool = None
        self.init_db()
    
    def get_connection(self):
        """Get database connection with retry logic"""
        max_retries = 3
        for attempt in range(max_retries):
            try:
                conn = psycopg2.connect(**DB_CONFIG)
                ACTIVE_CONNECTIONS.inc()
                return conn
            except psycopg2.Error as e:
                logger.error(f"Database connection attempt {attempt + 1} failed: {e}")
                if attempt == max_retries - 1:
                    raise
                time.sleep(2 ** attempt)  # Exponential backoff
    
    def close_connection(self, conn):
        """Close database connection"""
        if conn:
            conn.close()
            ACTIVE_CONNECTIONS.dec()
    
    def init_db(self):
        """Initialize database tables"""
        conn = None
        try:
            conn = self.get_connection()
            cursor = conn.cursor()
            
            # Create tasks table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS tasks (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    description TEXT,
                    status VARCHAR(50) DEFAULT 'pending',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Create index for better performance
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)
            """)
            
            conn.commit()
            logger.info("Database initialized successfully")
            
        except Exception as e:
            logger.error(f"Database initialization failed: {e}")
            if conn:
                conn.rollback()
            raise
        finally:
            self.close_connection(conn)


# Initialize database manager
db_manager = DatabaseManager()


@app.before_request
def before_request():
    """Set up request context"""
    g.start_time = time.time()


@app.after_request
def after_request(response):
    """Record metrics after each request"""
    duration = time.time() - g.start_time
    REQUEST_DURATION.observe(duration)
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.endpoint or 'unknown',
        status=response.status_code
    ).inc()
    return response


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for load balancer"""
    try:
        # Test database connectivity
        conn = db_manager.get_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT 1')
        cursor.fetchone()
        db_manager.close_connection(conn)
        
        return jsonify({
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat(),
            'version': '1.0.0'
        }), 200
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 503


@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint"""
    return prometheus_client.generate_latest()


@app.route('/api/tasks', methods=['GET'])
def get_tasks():
    """Get all tasks with optional filtering"""
    status_filter = request.args.get('status')
    limit = int(request.args.get('limit', 100))
    offset = int(request.args.get('offset', 0))
    
    conn = None
    try:
        conn = db_manager.get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        if status_filter:
            cursor.execute(
                "SELECT * FROM tasks WHERE status = %s ORDER BY created_at DESC LIMIT %s OFFSET %s",
                (status_filter, limit, offset)
            )
        else:
            cursor.execute(
                "SELECT * FROM tasks ORDER BY created_at DESC LIMIT %s OFFSET %s",
                (limit, offset)
            )
        
        tasks = cursor.fetchall()
        
        return jsonify({
            'tasks': [dict(task) for task in tasks],
            'count': len(tasks),
            'limit': limit,
            'offset': offset
        }), 200
        
    except Exception as e:
        logger.error(f"Failed to fetch tasks: {e}")
        return jsonify({'error': 'Failed to fetch tasks'}), 500
    finally:
        db_manager.close_connection(conn)


@app.route('/api/tasks', methods=['POST'])
def create_task():
    """Create a new task"""
    try:
        data = request.get_json()
        if not data or 'title' not in data:
            raise BadRequest("Title is required")
        
        title = data['title']
        description = data.get('description', '')
        status = data.get('status', 'pending')
        
        conn = db_manager.get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute(
            """
            INSERT INTO tasks (title, description, status) 
            VALUES (%s, %s, %s) 
            RETURNING *
            """,
            (title, description, status)
        )
        
        task = cursor.fetchone()
        conn.commit()
        
        logger.info(f"Created task: {task['id']}")
        return jsonify(dict(task)), 201
        
    except BadRequest as e:
        return jsonify({'error': str(e)}), 400
    except Exception as e:
        logger.error(f"Failed to create task: {e}")
        if conn:
            conn.rollback()
        return jsonify({'error': 'Failed to create task'}), 500
    finally:
        db_manager.close_connection(conn)


@app.route('/api/tasks/<int:task_id>', methods=['GET'])
def get_task(task_id):
    """Get a specific task by ID"""
    conn = None
    try:
        conn = db_manager.get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        cursor.execute("SELECT * FROM tasks WHERE id = %s", (task_id,))
        task = cursor.fetchone()
        
        if not task:
            raise NotFound("Task not found")
        
        return jsonify(dict(task)), 200
        
    except NotFound as e:
        return jsonify({'error': str(e)}), 404
    except Exception as e:
        logger.error(f"Failed to fetch task {task_id}: {e}")
        return jsonify({'error': 'Failed to fetch task'}), 500
    finally:
        db_manager.close_connection(conn)


@app.route('/api/tasks/<int:task_id>', methods=['PUT'])
def update_task(task_id):
    """Update an existing task"""
    conn = None
    try:
        data = request.get_json()
        if not data:
            raise BadRequest("Request body is required")
        
        conn = db_manager.get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # Check if task exists
        cursor.execute("SELECT id FROM tasks WHERE id = %s", (task_id,))
        if not cursor.fetchone():
            raise NotFound("Task not found")
        
        # Build dynamic update query
        update_fields = []
        values = []
        
        for field in ['title', 'description', 'status']:
            if field in data:
                update_fields.append(f"{field} = %s")
                values.append(data[field])
        
        if not update_fields:
            raise BadRequest("No valid fields to update")
        
        update_fields.append("updated_at = CURRENT_TIMESTAMP")
        values.append(task_id)
        
        cursor.execute(
            f"UPDATE tasks SET {', '.join(update_fields)} WHERE id = %s RETURNING *",
            values
        )
        
        task = cursor.fetchone()
        conn.commit()
        
        logger.info(f"Updated task: {task_id}")
        return jsonify(dict(task)), 200
        
    except (BadRequest, NotFound) as e:
        return jsonify({'error': str(e)}), 400 if isinstance(e, BadRequest) else 404
    except Exception as e:
        logger.error(f"Failed to update task {task_id}: {e}")
        if conn:
            conn.rollback()
        return jsonify({'error': 'Failed to update task'}), 500
    finally:
        db_manager.close_connection(conn)


@app.route('/api/tasks/<int:task_id>', methods=['DELETE'])
def delete_task(task_id):
    """Delete a task"""
    conn = None
    try:
        conn = db_manager.get_connection()
        cursor = conn.cursor()
        
        cursor.execute("DELETE FROM tasks WHERE id = %s", (task_id,))
        
        if cursor.rowcount == 0:
            raise NotFound("Task not found")
        
        conn.commit()
        
        logger.info(f"Deleted task: {task_id}")
        return '', 204
        
    except NotFound as e:
        return jsonify({'error': str(e)}), 404
    except Exception as e:
        logger.error(f"Failed to delete task {task_id}: {e}")
        if conn:
            conn.rollback()
        return jsonify({'error': 'Failed to delete task'}), 500
    finally:
        db_manager.close_connection(conn)


@app.route('/api/cpu-intensive', methods=['POST'])
def cpu_intensive_task():
    """CPU-intensive endpoint for testing autoscaling"""
    iterations = int(request.json.get('iterations', 100000))
    
    start_time = time.time()
    
    # Simulate CPU-intensive work
    result = 0
    for i in range(iterations):
        result += i ** 2
    
    duration = time.time() - start_time
    
    return jsonify({
        'result': result,
        'iterations': iterations,
        'duration_seconds': duration,
        'timestamp': datetime.utcnow().isoformat()
    }), 200


@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Not found'}), 404


@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500


if __name__ == '__main__':
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('DEBUG', 'False').lower() == 'true'
    
    logger.info(f"Starting application on port {port}")
    app.run(host='0.0.0.0', port=port, debug=debug)
