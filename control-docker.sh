#!/bin/bash

# Control Script for Docker Compose Test Environment
# Usage: ./control-docker.sh [command] [endpoint] [args...]

BASE_URL="http://localhost:8082"

show_help() {
    echo "Gatus Docker Test Environment Control Script"
    echo
    echo "Usage: $0 [command] [args...]"
    echo
    echo "Docker Commands:"
    echo "  up                       - Start all services (docker-compose up -d)"
    echo "  down                     - Stop all services (docker-compose down)"
    echo "  logs [service]           - Show logs for service (gatus, alertmanager, test-server)"
    echo "  status                   - Show service status"
    echo
    echo "Endpoint Commands:"
    echo "  list                     - List all endpoints and their status"
    echo "  fail <endpoint>          - Make endpoint fail"
    echo "  pass <endpoint>          - Make endpoint pass"
    echo "  toggle <endpoint>        - Toggle endpoint status"
    echo "  time                     - Show current time and time-based endpoint status"
    echo "  demo                     - Run a demonstration sequence"
    echo
    echo "Examples:"
    echo "  $0 up                    # Start the environment"
    echo "  $0 fail api              # Make API endpoint fail"
    echo "  $0 pass database         # Make database endpoint pass"
    echo "  $0 logs gatus            # Show Gatus logs"
    echo "  $0 demo                  # Run full demo"
    echo "  $0 down                  # Stop everything"
}

docker_up() {
    echo "🚀 Starting Docker Compose environment..."
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        echo "✅ Services started successfully"
        echo
        echo "🌐 Services available at:"
        echo "  - Alertmanager: http://localhost:9093"
        echo "  - Test Server:  http://localhost:8080"
        echo "  - HTTPBin:      http://localhost:8081"
        echo
        echo "📊 Start Gatus with:"
        echo "  ./gatus --config=config-docker.yaml"
        echo
        echo "⏳ Waiting for services to be ready..."
        sleep 5
        
        # Check service health
        check_services
    else
        echo "❌ Failed to start services"
        exit 1
    fi
}

docker_down() {
    echo "🛑 Stopping Docker Compose environment..."
    docker-compose down
    echo "✅ Services stopped"
}

docker_logs() {
    local service="$1"
    if [ -z "$service" ]; then
        echo "📋 Available services: alertmanager, test-server, httpbin"
        echo "Usage: $0 logs <service>"
        return 1
    fi
    
    echo "📄 Showing logs for $service..."
    docker-compose logs -f "$service"
}

docker_status() {
    echo "📊 Docker Compose Service Status:"
    echo "=================================="
    docker-compose ps
    echo
    
    echo "🔍 Service Health Checks:"
    check_services
}

check_services() {
    # Check Alertmanager
    if curl -s http://localhost:9093/api/v2/status > /dev/null 2>&1; then
        echo "✅ Alertmanager is responding"
    else
        echo "❌ Alertmanager is not responding"
    fi
    
    # Check Test Server
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "✅ Test Server is responding"
    else
        echo "❌ Test Server is not responding"
    fi
    
    # Check HTTPBin
    if curl -s http://localhost:8081/get > /dev/null 2>&1; then
        echo "✅ HTTPBin is responding"
    else
        echo "❌ HTTPBin is not responding"
    fi
}

list_endpoints() {
    echo "📋 Current endpoint status:"
    curl -s "$BASE_URL/control/" | jq -r '
        to_entries[] | 
        if .value.healthy then "🟢" else "🔴" end + " " + .key + " - " + .value.message
    ' 2>/dev/null || {
        echo "❌ Could not connect to test server or jq not available"
        echo "   Make sure Docker services are running: $0 up"
        exit 1
    }
}

endpoint_status() {
    local endpoint="$1"
    if [ -z "$endpoint" ]; then
        echo "❌ Endpoint name required"
        exit 1
    fi
    
    echo "📊 Status for endpoint '$endpoint':"
    curl -s "$BASE_URL/health/$endpoint" | jq '.' 2>/dev/null || {
        echo "❌ Could not get status for endpoint '$endpoint'"
        exit 1
    }
}

fail_endpoint() {
    local endpoint="$1"
    if [ -z "$endpoint" ]; then
        echo "❌ Endpoint name required"
        exit 1
    fi
    
    echo "🔴 Making endpoint '$endpoint' fail..."
    curl -s -X POST "$BASE_URL/control/$endpoint" \
        -H "Content-Type: application/json" \
        -d '{"healthy": false, "status": 503, "message": "Manually set to fail"}' | jq '.'
    
    echo "✅ Endpoint '$endpoint' is now failing"
}

pass_endpoint() {
    local endpoint="$1"
    if [ -z "$endpoint" ]; then
        echo "❌ Endpoint name required"
        exit 1
    fi
    
    echo "🟢 Making endpoint '$endpoint' pass..."
    curl -s -X POST "$BASE_URL/control/$endpoint" \
        -H "Content-Type: application/json" \
        -d '{"healthy": true, "status": 200, "message": "Manually set to pass"}' | jq '.'
    
    echo "✅ Endpoint '$endpoint' is now passing"
}

toggle_endpoint() {
    local endpoint="$1"
    if [ -z "$endpoint" ]; then
        echo "❌ Endpoint name required"
        exit 1
    fi
    
    # Get current status
    local current_status=$(curl -s "$BASE_URL/health/$endpoint" | jq -r '.healthy' 2>/dev/null)
    
    if [ "$current_status" = "true" ]; then
        fail_endpoint "$endpoint"
    elif [ "$current_status" = "false" ]; then
        pass_endpoint "$endpoint"
    else
        echo "❌ Could not determine current status of endpoint '$endpoint'"
        exit 1
    fi
}

show_time_status() {
    echo "🕐 Current time and time-based endpoint status:"
    echo
    
    local now=$(date)
    local minute=$(date +%M | sed 's/^0//')
    local second=$(date +%S | sed 's/^0//')
    
    echo "Current time: $now"
    echo "Minute: $minute ($([ $((minute % 2)) -eq 0 ] && echo "even - FAILING" || echo "odd - PASSING"))"
    echo "Second: $second ($([ $second -lt 20 ] && echo "<20 - FAILING" || echo ">=20 - PASSING"))"
    echo
    
    echo "📊 Time-based endpoint responses:"
    echo "Minute-based (/time-based):"
    curl -s "$BASE_URL/time-based" | jq '.'
    echo
    echo "Second-based (/second-based):"
    curl -s "$BASE_URL/second-based" | jq '.'
}

run_demo() {
    echo "🎬 Running Docker Compose Demo"
    echo "=============================="
    echo
    
    # Check if services are running
    if ! curl -s "$BASE_URL/" > /dev/null 2>&1; then
        echo "❌ Test server not responding. Starting services..."
        docker_up
        echo "⏳ Waiting for services to stabilize..."
        sleep 10
    fi
    
    echo "1️⃣ Current endpoint status:"
    list_endpoints
    echo
    
    echo "2️⃣ Making API endpoint fail..."
    fail_endpoint "api"
    sleep 2
    
    echo "3️⃣ Making database endpoint fail..."
    fail_endpoint "database"
    sleep 2
    
    echo "4️⃣ Current status after failures:"
    list_endpoints
    echo
    
    echo "5️⃣ Waiting 45 seconds for alerts to trigger..."
    echo "   Monitor Alertmanager: http://localhost:9093"
    echo "   Start Gatus: ./gatus --config=config-docker.yaml"
    for i in {45..1}; do
        echo -ne "   Waiting... ${i}s remaining\r"
        sleep 1
    done
    echo
    
    echo "6️⃣ Fixing API endpoint..."
    pass_endpoint "api"
    sleep 2
    
    echo "7️⃣ Fixing database endpoint..."
    pass_endpoint "database"
    sleep 2
    
    echo "8️⃣ Final status:"
    list_endpoints
    echo
    
    echo "9️⃣ Time-based status:"
    show_time_status
    echo
    
    echo "✅ Demo complete!"
    echo "   Check Alertmanager UI for alert activity: http://localhost:9093"
    echo "   Time-based endpoints will continue to toggle automatically."
}

# Main script logic
case "$1" in
    "up")
        docker_up
        ;;
    "down")
        docker_down
        ;;
    "logs")
        docker_logs "$2"
        ;;
    "status"|"ps")
        docker_status
        ;;
    "list"|"ls")
        list_endpoints
        ;;
    "fail"|"down-endpoint")
        fail_endpoint "$2"
        ;;
    "pass"|"up-endpoint")
        pass_endpoint "$2"
        ;;
    "toggle")
        toggle_endpoint "$2"
        ;;
    "time")
        show_time_status
        ;;
    "demo")
        run_demo
        ;;
    "help"|"-h"|"--help"|"")
        show_help
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo
        show_help
        exit 1
        ;;
esac
