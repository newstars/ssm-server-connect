#!/bin/bash

# SSM Server Connect - AWS Systems Manager Session Manager CLI Tool
# A user-friendly CLI tool for connecting to Linux servers via AWS SSM
# GitHub: https://github.com/your-repo/ssm-server-connect

set -euo pipefail

# Global Variables
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"
readonly DEFAULT_REGION="ap-northeast-2"
readonly GITHUB_REPO="newstars/ssm-server-connect"
readonly UPDATE_CHECK_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# AWS Configuration
AWS_PROFILE=""
AWS_REGION="${DEFAULT_REGION}"

# FZF Configuration
readonly FZF_PREVIEW_WINDOW="right:50%:wrap"
readonly FZF_HEIGHT="80%"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Temporary files
readonly TEMP_DIR="/tmp/${SCRIPT_NAME}_$$"
readonly INSTANCE_LIST_FILE="${TEMP_DIR}/instances.txt"
readonly PROFILE_LIST_FILE="${TEMP_DIR}/profiles.txt"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_MISSING_DEPS=1
readonly EXIT_AUTH_FAILED=2
readonly EXIT_NO_INSTANCES=3
readonly EXIT_CONNECTION_FAILED=4
readonly EXIT_USER_CANCELLED=5

# Check if all required tools are installed
check_requirements() {
    local missing_tools=()
    local all_good=true
    
    echo -e "${BLUE}Checking system requirements...${NC}"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
        all_good=false
        echo -e "${RED}✗ AWS CLI not found${NC}"
    else
        # Check AWS CLI version (v2 preferred)
        local aws_version
        aws_version=$(aws --version 2>&1 | head -n1)
        if [[ $aws_version == *"aws-cli/2"* ]]; then
            echo -e "${GREEN}✓ AWS CLI v2 found${NC}"
        elif [[ $aws_version == *"aws-cli/1"* ]]; then
            echo -e "${YELLOW}⚠ AWS CLI v1 found (v2 recommended)${NC}"
        else
            echo -e "${GREEN}✓ AWS CLI found${NC}"
        fi
    fi
    
    # Check Session Manager Plugin
    if ! command -v session-manager-plugin &> /dev/null; then
        missing_tools+=("session-manager-plugin")
        all_good=false
        echo -e "${RED}✗ AWS Session Manager Plugin not found${NC}"
    else
        echo -e "${GREEN}✓ AWS Session Manager Plugin found${NC}"
    fi
    
    # Check FZF
    if ! command -v fzf &> /dev/null; then
        missing_tools+=("fzf")
        all_good=false
        echo -e "${RED}✗ FZF (fuzzy finder) not found${NC}"
    else
        echo -e "${GREEN}✓ FZF (fuzzy finder) found${NC}"
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
        all_good=false
        echo -e "${RED}✗ jq (JSON processor) not found${NC}"
    else
        echo -e "${GREEN}✓ jq (JSON processor) found${NC}"
    fi
    
    # If any tools are missing, show installation instructions
    if [[ "$all_good" == false ]]; then
        echo
        echo -e "${RED}Missing required tools detected!${NC}"
        echo -e "${YELLOW}Please install the following tools using Homebrew:${NC}"
        echo
        
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "aws-cli")
                    echo -e "  ${BLUE}AWS CLI:${NC}"
                    echo -e "    brew install awscli"
                    echo
                    ;;
                "session-manager-plugin")
                    echo -e "  ${BLUE}AWS Session Manager Plugin:${NC}"
                    echo -e "    brew install --cask session-manager-plugin"
                    echo
                    ;;
                "fzf")
                    echo -e "  ${BLUE}FZF (Fuzzy Finder):${NC}"
                    echo -e "    brew install fzf"
                    echo
                    ;;
                "jq")
                    echo -e "  ${BLUE}jq (JSON Processor):${NC}"
                    echo -e "    brew install jq"
                    echo
                    ;;
            esac
        done
        
        echo -e "${YELLOW}After installation, please run this script again.${NC}"
        echo
        echo -e "${BLUE}For more information:${NC}"
        echo -e "  AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        echo -e "  Session Manager Plugin: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
        echo -e "  FZF: https://github.com/junegunn/fzf"
        
        exit "${EXIT_MISSING_DEPS}"
    fi
    
    echo -e "${GREEN}✓ All required tools are installed${NC}"
    echo
}

# Utility Functions

# Show spinner animation while a background process is running
show_spinner() {
    local pid=$1
    local msg="$2"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r%s %s" "${spin:$i:1}" "$msg"
        i=$(( (i+1) % ${#spin} ))
        sleep 0.1
    done
    printf "\r"
}

# Show progress bar with percentage
show_progress() {
    local current=$1
    local total=$2
    local msg="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 5))
    local empty=$((20 - filled))
    
    printf "\r%s [%*s%*s] %d%% (%d/%d)" "$msg" $filled "" $empty "" $percent $current $total | 
        tr ' ' '█' | sed 's/█/ /g; s/^\([^[]\+\[\)\([█]*\)/\1\2/; s/\([█]*\)\([^]]*\]\)/\1░\2/g'
}

# Execute AWS commands with proper error handling
aws_exec() {
    local output
    local exit_code
    
    # Execute the AWS command and capture both output and exit code
    if ! output=$("$@" 2>&1); then
        exit_code=$?
        echo -e "${RED}❌ AWS command failed: $*${NC}" >&2
        
        # Provide specific guidance based on common error patterns
        if echo "$output" | grep -q "Unable to locate credentials"; then
            echo -e "${YELLOW}Credentials not found. Please run 'aws configure' or set up AWS SSO${NC}" >&2
        elif echo "$output" | grep -q "The security token included in the request is invalid"; then
            echo -e "${YELLOW}Security token is invalid. Please refresh your AWS credentials${NC}" >&2
        elif echo "$output" | grep -q "An error occurred.*when calling.*operation"; then
            echo -e "${YELLOW}AWS API error. Check your permissions and region settings${NC}" >&2
        elif echo "$output" | grep -q "Could not connect to the endpoint URL"; then
            echo -e "${YELLOW}Network connectivity issue. Check your internet connection and region${NC}" >&2
        fi
        
        echo -e "${RED}$output${NC}" >&2
        return $exit_code
    fi
    
    echo "$output"
    return 0
}

# AWS Profile Management Functions

# Extract AWS profiles from config and credentials files
select_profile() {
    local profiles=()
    local config_file="$HOME/.aws/config"
    local credentials_file="$HOME/.aws/credentials"
    
    echo -e "${BLUE}Loading AWS profiles...${NC}"
    
    # Check if AWS config files exist
    if [[ ! -f "$config_file" && ! -f "$credentials_file" ]]; then
        echo -e "${RED}❌ AWS configuration files not found${NC}"
        echo -e "${YELLOW}Please run 'aws configure' or 'aws configure sso' to set up AWS CLI${NC}"
        exit "${EXIT_AUTH_FAILED}"
    fi
    
    # Extract profiles from ~/.aws/config
    if [[ -f "$config_file" ]]; then
        while IFS= read -r line; do
            if [[ $line =~ ^\[profile[[:space:]]+([^]]+)\] ]]; then
                profiles+=("${BASH_REMATCH[1]}")
            elif [[ $line =~ ^\[default\] ]]; then
                profiles+=("default")
            fi
        done < "$config_file"
    fi
    
    # Extract profiles from ~/.aws/credentials
    if [[ -f "$credentials_file" ]]; then
        while IFS= read -r line; do
            if [[ $line =~ ^\[([^]]+)\] ]]; then
                local profile_name="${BASH_REMATCH[1]}"
                # Add profile if not already in the list
                if [[ ! " ${profiles[*]} " =~ " ${profile_name} " ]]; then
                    profiles+=("$profile_name")
                fi
            fi
        done < "$credentials_file"
    fi
    
    # Check if any profiles were found
    if [[ ${#profiles[@]} -eq 0 ]]; then
        echo -e "${RED}❌ No AWS profiles found${NC}"
        echo -e "${YELLOW}Please set up AWS CLI with one of these methods:${NC}"
        echo -e "  • For regular AWS credentials: aws configure"
        echo -e "  • For AWS SSO: aws configure sso"
        echo -e "  • For temporary credentials: export AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
        echo
        echo -e "${BLUE}For more information:${NC}"
        echo -e "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html"
        exit "${EXIT_AUTH_FAILED}"
    fi
    
    # Sort profiles alphabetically
    IFS=$'\n' profiles=($(sort <<<"${profiles[*]}"))
    unset IFS
    
    # Add back navigation option
    local fzf_options=(".. (뒤로 가기)")
    fzf_options+=("${profiles[@]}")
    
    # Create temporary file for FZF
    printf "%s\n" "${fzf_options[@]}" > "${PROFILE_LIST_FILE}"
    
    echo -e "${GREEN}✓ Found ${#profiles[@]} AWS profile(s)${NC}"
    echo
    
    # Use FZF to select profile
    local selected_profile
    selected_profile=$(cat "${PROFILE_LIST_FILE}" | fzf \
        --height="${FZF_HEIGHT}" \
        --prompt="Select AWS Profile: " \
        --header="Use ↑↓ to navigate, Enter to select, Esc to cancel" \
        --border \
        --preview="echo 'Profile: {}' && echo '' && if [[ '{}' != '.. (뒤로 가기)' ]]; then aws configure list --profile {} 2>/dev/null || echo 'Profile configuration not available'; fi" \
        --preview-window="${FZF_PREVIEW_WINDOW}" 2>/dev/null)
    
    # Handle user selection
    if [[ -z "$selected_profile" ]]; then
        echo -e "${YELLOW}Profile selection cancelled${NC}"
        echo -e "${BLUE}Exiting SSM Server Connect...${NC}"
        return "${EXIT_USER_CANCELLED}"
    fi
    
    if [[ "$selected_profile" == ".. (뒤로 가기)" ]]; then
        echo -e "${YELLOW}Going back...${NC}"
        return "${EXIT_USER_CANCELLED}"
    fi
    
    # Set the selected profile
    AWS_PROFILE="$selected_profile"
    export AWS_PROFILE
    
    echo -e "${GREEN}✓ Selected AWS profile: ${AWS_PROFILE}${NC}"
    echo
    
    return 0
}

# Check AWS authentication status and perform SSO login if needed
check_aws_auth() {
    local profile="$1"
    
    echo -e "${BLUE}Checking AWS authentication for profile: ${profile}${NC}"
    
    # Test authentication by calling STS get-caller-identity
    local auth_output
    local auth_exit_code
    
    if auth_output=$(aws sts get-caller-identity --profile "$profile" 2>&1); then
        # Parse the identity information
        local account_id
        local user_arn
        
        account_id=$(echo "$auth_output" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
        user_arn=$(echo "$auth_output" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
        
        echo -e "${GREEN}✓ AWS authentication successful${NC}"
        echo -e "  Account ID: ${account_id}"
        echo -e "  User/Role: ${user_arn}"
        echo
        return 0
    else
        auth_exit_code=$?
        echo -e "${YELLOW}⚠ AWS authentication failed${NC}"
        
        # Check if this is an SSO profile that needs login
        if echo "$auth_output" | grep -q "SSO session"; then
            echo -e "${BLUE}Detected SSO profile. Attempting automatic login...${NC}"
            
            # Attempt SSO login
            if aws sso login --profile "$profile"; then
                echo -e "${GREEN}✓ SSO login successful${NC}"
                
                # Verify authentication again
                if aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
                    echo -e "${GREEN}✓ AWS authentication verified after SSO login${NC}"
                    echo
                    return 0
                else
                    echo -e "${RED}❌ Authentication verification failed after SSO login${NC}"
                    exit "${EXIT_AUTH_FAILED}"
                fi
            else
                echo -e "${RED}❌ SSO login failed${NC}"
                echo -e "${YELLOW}Please check your SSO configuration and try again${NC}"
                exit "${EXIT_AUTH_FAILED}"
            fi
        elif echo "$auth_output" | grep -q "could not be found"; then
            echo -e "${RED}❌ AWS profile '${profile}' not found${NC}"
            echo -e "${YELLOW}Please check your AWS configuration${NC}"
            exit "${EXIT_AUTH_FAILED}"
        elif echo "$auth_output" | grep -q "No credentials"; then
            echo -e "${RED}❌ No credentials configured for profile '${profile}'${NC}"
            echo -e "${YELLOW}Please run 'aws configure --profile ${profile}' to set up credentials${NC}"
            exit "${EXIT_AUTH_FAILED}"
        elif echo "$auth_output" | grep -q "ExpiredToken\|TokenRefreshRequired"; then
            echo -e "${RED}❌ AWS credentials have expired${NC}"
            echo -e "${YELLOW}Please refresh your credentials and try again${NC}"
            
            # Check if this might be an SSO profile
            local config_file="$HOME/.aws/config"
            if [[ -f "$config_file" ]] && grep -A 10 "^\[profile $profile\]" "$config_file" | grep -q "sso_"; then
                echo -e "${BLUE}Attempting SSO login for expired credentials...${NC}"
                if aws sso login --profile "$profile"; then
                    echo -e "${GREEN}✓ SSO login successful${NC}"
                    return 0
                fi
            fi
            
            exit "${EXIT_AUTH_FAILED}"
        else
            echo -e "${RED}❌ Authentication failed with unknown error${NC}"
            echo -e "${RED}Error details: ${auth_output}${NC}"
            exit "${EXIT_AUTH_FAILED}"
        fi
    fi
}

# SSM Instance Management Functions

# List SSM managed instances (Linux only, online status)
list_ssm_instances() {
    local region="$1"
    local profile="$2"
    
    echo -e "${BLUE}Querying SSM managed instances in region: ${region}${NC}"
    
    # Query SSM for managed instances
    local ssm_output
    # Set AWS CLI optimizations for faster queries
    export AWS_CLI_READ_TIMEOUT=10
    export AWS_CLI_MAX_ATTEMPTS=2
    
    local query_cmd=(
        aws ssm describe-instance-information
        --profile "$profile"
        --region "$region"
        --filters "Key=PingStatus,Values=Online" "Key=PlatformTypes,Values=Linux"
        --query 'InstanceInformationList[*].{InstanceId:InstanceId,PlatformType:PlatformType,PlatformName:PlatformName,PingStatus:PingStatus,LastPingDateTime:LastPingDateTime,AgentVersion:AgentVersion}'
        --output json
        --max-items 1000
    )
    
    # Execute the query with spinner
    local temp_output="${TEMP_DIR}/ssm_query.json"
    
    # Run AWS command in background with spinner
    (
        if ! ssm_output=$(aws_exec "${query_cmd[@]}" 2>&1); then
            echo "ERROR: $ssm_output" > "$temp_output"
            exit 1
        fi
        echo "$ssm_output" > "$temp_output"
    ) &
    
    local query_pid=$!
    show_spinner $query_pid "Querying SSM managed instances..."
    
    # Wait for the background process and check result
    if ! wait $query_pid; then
        echo -e "${RED}❌ Failed to query SSM instances${NC}"
        if [[ -f "$temp_output" ]]; then
            local error_msg
            error_msg=$(cat "$temp_output")
            if [[ "$error_msg" == ERROR:* ]]; then
                echo -e "${RED}${error_msg#ERROR: }${NC}"
            fi
        fi
        return 1
    fi
    
    # Read the results
    if [[ ! -f "$temp_output" ]]; then
        echo -e "${RED}❌ No output file generated${NC}"
        return 1
    fi
    
    ssm_output=$(cat "$temp_output")
    
    # Parse JSON and check if we have instances
    local instance_count
    if ! instance_count=$(echo "$ssm_output" | jq '. | length' 2>/dev/null); then
        echo -e "${RED}❌ Failed to parse SSM response${NC}"
        echo -e "${YELLOW}The response may not be valid JSON. This could indicate:${NC}"
        echo -e "  • AWS CLI version compatibility issues"
        echo -e "  • Network connectivity problems"
        echo -e "  • AWS service temporary unavailability"
        echo
        echo -e "${BLUE}Raw response (first 500 characters):${NC}"
        echo "$ssm_output" | head -c 500
        echo
        return 1
    fi
    
    if [[ "$instance_count" -eq 0 ]]; then
        echo -e "${YELLOW}⚠ No SSM managed Linux instances found in region ${region}${NC}"
        echo -e "${BLUE}Make sure you have:${NC}"
        echo -e "  • EC2 instances with SSM Agent installed and running"
        echo -e "  • Instances with proper IAM role (AmazonSSMManagedInstanceCore)"
        echo -e "  • Instances in 'Online' status"
        echo -e "  • Linux platform instances"
        echo
        return 1
    fi
    
    echo -e "${GREEN}✓ Found ${instance_count} SSM managed Linux instance(s)${NC}"
    
    # Store the raw SSM data for later use
    echo "$ssm_output" > "${TEMP_DIR}/ssm_instances.json"
    
    return 0
}

# Get detailed instance information from EC2 API
get_instance_details() {
    local instance_id="$1"
    local region="$2"
    local profile="$3"
    
    # Query EC2 for instance details
    local ec2_output
    local query_cmd=(
        aws ec2 describe-instances
        --profile "$profile"
        --region "$region"
        --instance-ids "$instance_id"
        --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,InstanceType:InstanceType,State:State.Name,PrivateIpAddress:PrivateIpAddress,PublicIpAddress:PublicIpAddress,Tags:Tags}'
        --output json
    )
    
    # Execute the query
    if ! ec2_output=$(aws_exec "${query_cmd[@]}" 2>/dev/null); then
        # If EC2 query fails, return minimal info
        echo "{\"InstanceId\":\"$instance_id\",\"Name\":\"Unknown\",\"PrivateIpAddress\":\"Unknown\",\"PublicIpAddress\":null,\"InstanceType\":\"Unknown\",\"State\":\"Unknown\"}"
        return 0
    fi
    
    # Parse the EC2 response and extract relevant information
    local instance_data
    instance_data=$(echo "$ec2_output" | jq -r '
        .[] | .[] | 
        {
            InstanceId: .InstanceId,
            Name: (.Tags // [] | map(select(.Key == "Name")) | .[0].Value // "No Name"),
            PrivateIpAddress: (.PrivateIpAddress // "No Private IP"),
            PublicIpAddress: (.PublicIpAddress // null),
            InstanceType: .InstanceType,
            State: .State
        }
    ' 2>/dev/null)
    
    if [[ -z "$instance_data" || "$instance_data" == "null" ]]; then
        # Fallback if parsing fails
        echo "{\"InstanceId\":\"$instance_id\",\"Name\":\"Unknown\",\"PrivateIpAddress\":\"Unknown\",\"PublicIpAddress\":null,\"InstanceType\":\"Unknown\",\"State\":\"Unknown\"}"
    else
        echo "$instance_data"
    fi
    
    return 0
}

# Format instance information for FZF display
format_instance_display() {
    local ssm_data="$1"
    local ec2_data="$2"
    
    # Extract information from both SSM and EC2 data
    local instance_id
    local name
    local private_ip
    local public_ip
    local instance_type
    local platform_name
    local ping_status
    local agent_version
    
    instance_id=$(echo "$ssm_data" | jq -r '.InstanceId // "Unknown"')
    platform_name=$(echo "$ssm_data" | jq -r '.PlatformName // "Linux"')
    ping_status=$(echo "$ssm_data" | jq -r '.PingStatus // "Unknown"')
    agent_version=$(echo "$ssm_data" | jq -r '.AgentVersion // "Unknown"')
    
    name=$(echo "$ec2_data" | jq -r '.Name // "No Name"')
    private_ip=$(echo "$ec2_data" | jq -r '.PrivateIpAddress // "No Private IP"')
    public_ip=$(echo "$ec2_data" | jq -r '.PublicIpAddress // null')
    instance_type=$(echo "$ec2_data" | jq -r '.InstanceType // "Unknown"')
    
    # Format the display string
    local display_name
    if [[ "$name" != "No Name" && "$name" != "Unknown" ]]; then
        display_name="$name ($instance_id)"
    else
        display_name="$instance_id"
    fi
    
    # Create formatted output for FZF
    local ip_display="$private_ip"
    if [[ "$public_ip" != "null" && -n "$public_ip" ]]; then
        ip_display="$private_ip / $public_ip"
    fi
    
    # Add SSM status indicator with more nuanced checking
    local ssm_status="�"   # Yellow circle for unknown/needs testing
    
    if [[ "$ping_status" == "Online" ]]; then
        # Check agent version - older versions may have issues
        if [[ "$agent_version" != "Unknown" && "$agent_version" != "null" ]]; then
            # Extract major version number
            local major_version
            major_version=$(echo "$agent_version" | cut -d. -f1)
            if [[ "$major_version" -ge 3 ]]; then
                ssm_status="O"  # Ready
            else
                ssm_status="?"  # Check needed for potentially outdated
            fi
        else
            ssm_status="?"  # Check needed for unknown agent version
        fi
    else
        ssm_status="X"  # Not ready
    fi
    
    # Format: "Status Display Name | IP Address | Instance Type | Platform"
    printf "%s %-48s | %-25s | %-12s | %s" \
        "$ssm_status" \
        "$display_name" \
        "$ip_display" \
        "$instance_type" \
        "$platform_name"
}

# Create detailed preview information for FZF
create_fzf_preview() {
    local selected_line="$1"
    local ssm_file="$2"
    local ec2_details_file="$3"
    
    # Handle back navigation option
    if [[ "$selected_line" == ".. (뒤로 가기)" ]]; then
        echo "═══════════════════════════════════════════════════════════════"
        echo "                    NAVIGATION"
        echo "═══════════════════════════════════════════════════════════════"
        echo
        echo "  ← Go back to AWS profile selection"
        echo
        echo "  Press Enter to return to profile selection"
        echo "  Press Esc to cancel and exit"
        echo
        echo "═══════════════════════════════════════════════════════════════"
        return 0
    fi
    
    # Extract instance ID from the formatted line
    # Format: "Display Name | IP Address | Instance Type | Platform"
    local instance_id
    if [[ "$selected_line" =~ \(([i-][0-9a-f]+)\) ]]; then
        instance_id="${BASH_REMATCH[1]}"
    elif [[ "$selected_line" =~ ^([i-][0-9a-f]+) ]]; then
        instance_id="${BASH_REMATCH[1]}"
    elif [[ "$selected_line" =~ ([i-][0-9a-f]+) ]]; then
        instance_id="${BASH_REMATCH[1]}"
    else
        echo "Unable to parse instance ID from selection: $selected_line"
        return 1
    fi
    
    # Find the SSM data for this instance
    local ssm_data
    ssm_data=$(jq --arg id "$instance_id" '.[] | select(.InstanceId == $id)' "$ssm_file" 2>/dev/null)
    
    if [[ -z "$ssm_data" ]]; then
        echo "Instance information not available for $instance_id"
        return 1
    fi
    
    # Get EC2 details if available
    local ec2_data="{}"
    if [[ -f "$ec2_details_file" ]]; then
        ec2_data=$(jq --arg id "$instance_id" '.[$id] // {}' "$ec2_details_file" 2>/dev/null || echo "{}")
    fi
    
    # Extract information
    local name platform_name ping_status last_ping agent_version
    local private_ip public_ip instance_type state
    
    name=$(echo "$ec2_data" | jq -r '.Name // "No Name"')
    platform_name=$(echo "$ssm_data" | jq -r '.PlatformName // "Linux"')
    ping_status=$(echo "$ssm_data" | jq -r '.PingStatus // "Unknown"')
    last_ping=$(echo "$ssm_data" | jq -r '.LastPingDateTime // "Unknown"')
    agent_version=$(echo "$ssm_data" | jq -r '.AgentVersion // "Unknown"')
    
    private_ip=$(echo "$ec2_data" | jq -r '.PrivateIpAddress // "Unknown"')
    public_ip=$(echo "$ec2_data" | jq -r '.PublicIpAddress // null')
    instance_type=$(echo "$ec2_data" | jq -r '.InstanceType // "Unknown"')
    state=$(echo "$ec2_data" | jq -r '.State // "Unknown"')
    
    # Format the preview
    echo "═══════════════════════════════════════════════════════════════"
    echo "                    INSTANCE DETAILS"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    echo "Instance Information:"
    echo "  Instance ID:      $instance_id"
    echo "  Name:            $name"
    echo "  Instance Type:   $instance_type"
    echo "  State:           $state"
    echo
    echo "Network Information:"
    echo "  Private IP:      $private_ip"
    if [[ "$public_ip" != "null" && -n "$public_ip" ]]; then
        echo "  Public IP:       $public_ip"
    else
        echo "  Public IP:       Not assigned"
    fi
    echo
    echo "SSM Information:"
    echo "  Platform:        $platform_name"
    echo "  Ping Status:     $ping_status"
    echo "  Agent Version:   $agent_version"
    echo "  Last Ping:       $last_ping"
    echo
    echo "Connection Status:"
    if [[ "$ping_status" == "Online" ]]; then
        # Check agent version for more accurate status
        local major_version
        if [[ "$agent_version" != "Unknown" && "$agent_version" != "null" ]]; then
            major_version=$(echo "$agent_version" | cut -d. -f1)
            if [[ "$major_version" -ge 3 ]]; then
                echo "  O Ready for Session Manager connection"
                echo "  Agent Version: $agent_version (Compatible)"
            else
                echo "  ? May need verification (older agent)"
                echo "  Agent Version: $agent_version (Consider updating)"
            fi
        else
            echo "  ? Needs verification before connection"
            echo "  Agent Version: Unknown (will test on connection)"
        fi
    else
        echo "  X Not available for SSM connection"
        echo "  Status: $ping_status"
        echo
        echo "Possible Issues:"
        case "$ping_status" in
            "Connection Lost")
                echo "  • Network connectivity problems"
                echo "  • SSM Agent stopped responding"
                ;;
            "Inactive")
                echo "  • SSM Agent not running"
                echo "  • Instance may be stopped"
                ;;
            "Unknown"|"")
                echo "  • SSM Agent not installed"
                echo "  • IAM role missing required permissions"
                echo "  • Network/firewall blocking SSM endpoints"
                ;;
            *)
                echo "  • Check SSM Agent status and logs"
                echo "  • Verify IAM permissions and network connectivity"
                ;;
        esac
        echo
        echo "Quick Fixes:"
        echo "  1. sudo systemctl restart amazon-ssm-agent"
        echo "  2. Check IAM role has AmazonSSMManagedInstanceCore"
        echo "  3. Verify security groups allow HTTPS outbound"
    fi
    echo
    echo "═══════════════════════════════════════════════════════════════"
}

# Select instance using FZF interface
select_instance() {
    local region="$1"
    local profile="$2"
    local ssm_file="${TEMP_DIR}/ssm_instances.json"
    local ec2_details_file="${TEMP_DIR}/ec2_details.json"
    local instance_list_file="${TEMP_DIR}/formatted_instances.txt"
    
    echo -e "${BLUE}Preparing instance selection interface...${NC}" >&2
    
    # Check if we have SSM instances data
    if [[ ! -f "$ssm_file" ]]; then
        echo -e "${RED}❌ SSM instances data not found${NC}"
        return 1
    fi
    
    # Read SSM instances
    local ssm_instances
    ssm_instances=$(cat "$ssm_file")
    
    # Create formatted instance list for FZF
    local formatted_instances=()
    
    # Add back navigation option
    formatted_instances+=(".. (뒤로 가기)")
    
    # Process each instance
    while IFS= read -r instance_data; do
        if [[ -n "$instance_data" && "$instance_data" != "null" ]]; then
            local instance_id
            instance_id=$(echo "$instance_data" | jq -r '.InstanceId')
            
            # Get EC2 data for this instance
            local ec2_data="{}"
            if [[ -f "$ec2_details_file" ]]; then
                ec2_data=$(jq --arg id "$instance_id" '.[$id] // {}' "$ec2_details_file" 2>/dev/null || echo "{}")
            fi
            
            # Format the instance for display
            local formatted_line
            formatted_line=$(format_instance_display "$instance_data" "$ec2_data")
            
            if [[ -n "$formatted_line" ]]; then
                formatted_instances+=("$formatted_line")
            fi
        fi
    done < <(echo "$ssm_instances" | jq -c '.[]')
    
    # Check if we have any instances to display
    if [[ ${#formatted_instances[@]} -le 1 ]]; then
        echo -e "${YELLOW}⚠ No instances available for selection${NC}"
        return 1
    fi
    
    # Write formatted instances to file for FZF
    printf "%s\n" "${formatted_instances[@]}" > "$instance_list_file"
    
    echo -e "${GREEN}✓ Found $((${#formatted_instances[@]} - 1)) instance(s) available${NC}" >&2
    echo
    
    # Create preview script for FZF
    local preview_script="${TEMP_DIR}/preview.sh"
    cat > "$preview_script" << EOF
#!/bin/bash
source "${BASH_SOURCE[0]}"
create_fzf_preview "\$1" "$ssm_file" "$ec2_details_file"
EOF
    chmod +x "$preview_script"
    
    # Count instances by status
    local ready_count=0
    local check_needed_count=0
    local not_ready_count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^O ]]; then
            ((ready_count++))
        elif [[ "$line" =~ ^\? ]]; then
            ((check_needed_count++))
        elif [[ "$line" =~ ^X ]]; then
            ((not_ready_count++))
        fi
    done < "$instance_list_file"
    
    # Show summary
    echo -e "${GREEN}O $ready_count ready${NC} | ${YELLOW}? $check_needed_count need verification${NC} | ${RED}X $not_ready_count not ready${NC}" >&2
    if [[ $check_needed_count -gt 0 ]]; then
        echo -e "${BLUE}💡 ? instances will be tested when selected${NC}"
    fi
    echo
    
    # Use FZF to select instance
    local selected_instance
    selected_instance=$(cat "$instance_list_file" | fzf \
        --height="${FZF_HEIGHT}" \
        --prompt="Select Instance: " \
        --header="O=Ready ?=Check Needed X=Not Ready | Use ↑↓ to navigate, Enter to connect, Esc to cancel" \
        --border \
        --preview="$preview_script {}" \
        --preview-window="${FZF_PREVIEW_WINDOW}" \
        --bind="ctrl-r:reload(cat $instance_list_file)" \
        --bind="ctrl-/:toggle-preview" 2>/dev/null)
    
    # Handle user selection
    if [[ -z "$selected_instance" ]]; then
        echo -e "${YELLOW}Selection cancelled${NC}"
        return 2  # User cancelled
    fi
    
    if [[ "$selected_instance" == ".. (뒤로 가기)" ]]; then
        echo -e "${YELLOW}Going back to profile selection...${NC}"
        return 3  # Go back
    fi
    
    # Extract instance ID from selection
    local selected_instance_id
    
    if [[ "$selected_instance" =~ \((i-[0-9a-f]+)\) ]]; then
        # Format: "Name (i-1234567890abcdef0) | ..."
        selected_instance_id="${BASH_REMATCH[1]}"
    elif [[ "$selected_instance" =~ ^(i-[0-9a-f]+) ]]; then
        # Format: "i-1234567890abcdef0 | ..."
        selected_instance_id="${BASH_REMATCH[1]}"
    elif [[ "$selected_instance" =~ (i-[0-9a-f]+) ]]; then
        # Fallback: find any instance ID pattern
        selected_instance_id="${BASH_REMATCH[1]}"
    else
        echo -e "${RED}❌ Unable to parse instance ID from selection: $selected_instance${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Selected instance: ${selected_instance_id}${NC}" >&2
    echo "$selected_instance_id"
    
    return 0
}

# Combine SSM and EC2 data for all instances (OPTIMIZED)
enrich_instance_data() {
    local region="$1"
    local profile="$2"
    local ssm_file="${TEMP_DIR}/ssm_instances.json"
    local ec2_details_file="${TEMP_DIR}/ec2_details.json"
    
    echo -e "${BLUE}Enriching instance data with EC2 information...${NC}"
    
    # Read SSM instances
    local ssm_instances
    ssm_instances=$(cat "$ssm_file")
    
    # Get list of instance IDs
    local instance_ids
    instance_ids=$(echo "$ssm_instances" | jq -r '.[].InstanceId' | tr '\n' ' ')
    
    if [[ -z "$instance_ids" ]]; then
        echo -e "${YELLOW}⚠ No instances to enrich${NC}"
        echo "{}" > "$ec2_details_file"
        return 1
    fi
    
    # OPTIMIZED: Single batch EC2 API call for all instances
    echo -e "${BLUE}Fetching EC2 details for all instances in one call...${NC}"
    
    # Set AWS CLI optimizations
    export AWS_CLI_READ_TIMEOUT=10
    export AWS_CLI_MAX_ATTEMPTS=2
    
    local ec2_query_cmd=(
        aws ec2 describe-instances
        --profile "$profile"
        --region "$region"
        --instance-ids $instance_ids
        --query 'Reservations[*].Instances[*].{InstanceId:InstanceId,InstanceType:InstanceType,PrivateIpAddress:PrivateIpAddress,PublicIpAddress:PublicIpAddress,Tags:Tags[?Key==`Name`||Key==`Environment`||Key==`Role`||Key==`Service`||Key==`Owner`||Key==`Team`]}'
        --output json
    )
    
    local ec2_output
    if ec2_output=$(aws_exec "${ec2_query_cmd[@]}" 2>&1); then
        # Process the batch response and create indexed object
        local processed_data
        processed_data=$(echo "$ec2_output" | jq -r '
            [.[][] | select(.InstanceId != null)] | 
            reduce .[] as $item ({}; 
                . + {
                    ($item.InstanceId): {
                        InstanceId: $item.InstanceId,
                        Name: (($item.Tags // []) | map(select(.Key == "Name")) | .[0].Value // "No Name"),
                        PrivateIpAddress: ($item.PrivateIpAddress // "No Private IP"),
                        PublicIpAddress: ($item.PublicIpAddress // null),
                        InstanceType: ($item.InstanceType // "Unknown"),
                        Environment: (($item.Tags // []) | map(select(.Key == "Environment" or .Key == "Env")) | .[0].Value // ""),
                        Role: (($item.Tags // []) | map(select(.Key == "Role" or .Key == "Service")) | .[0].Value // ""),
                        Owner: (($item.Tags // []) | map(select(.Key == "Owner" or .Key == "Team")) | .[0].Value // "")
                    }
                }
            )
        ')
        
        echo "$processed_data" > "$ec2_details_file"
        echo -e "${GREEN}✓ EC2 data enrichment complete (batch optimized)${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to fetch EC2 details: $ec2_output${NC}"
        echo -e "${BLUE}Creating minimal EC2 data...${NC}"
        
        # Create minimal data structure for failed cases
        echo "$ssm_instances" | jq -r '
            reduce .[] as $item ({}; 
                . + {
                    ($item.InstanceId): {
                        InstanceId: $item.InstanceId,
                        Name: "Unknown",
                        PrivateIpAddress: "Unknown",
                        PublicIpAddress: null,
                        InstanceType: "Unknown",
                        Environment: "",
                        Role: "",
                        Owner: ""
                    }
                }
            )
        ' > "$ec2_details_file"
    fi
    
    return 0
}

# Navigation and User Input Handling Functions

# Handle user cancellation gracefully
handle_user_cancellation() {
    local context="$1"
    local message="${2:-Operation cancelled by user}"
    
    echo
    echo -e "${YELLOW}$message${NC}"
    
    case "$context" in
        "profile_selection")
            echo -e "${BLUE}Exiting SSM Server Connect...${NC}"
            exit "${EXIT_USER_CANCELLED}"
            ;;
        "instance_selection")
            echo -e "${BLUE}Returning to profile selection...${NC}"
            return 3  # Signal to restart profile selection
            ;;
        "connection")
            echo -e "${BLUE}Returning to instance selection...${NC}"
            return 2  # Signal to return to instance selection
            ;;
        *)
            echo -e "${BLUE}Exiting...${NC}"
            exit "${EXIT_USER_CANCELLED}"
            ;;
    esac
}

# Handle navigation back to previous step
handle_navigation_back() {
    local current_step="$1"
    
    case "$current_step" in
        "instance_selection")
            echo -e "${BLUE}Going back to profile selection...${NC}"
            return 3  # Signal to restart profile selection
            ;;
        "connection")
            echo -e "${BLUE}Returning to instance selection...${NC}"
            return 2  # Signal to return to instance selection
            ;;
        *)
            echo -e "${BLUE}Exiting...${NC}"
            exit "${EXIT_USER_CANCELLED}"
            ;;
    esac
}

# Display user-friendly error messages
display_user_error() {
    local error_type="$1"
    local context="$2"
    local details="$3"
    
    echo
    echo -e "${RED}❌ Error: $error_type${NC}"
    
    case "$error_type" in
        "no_selection")
            echo -e "${YELLOW}No selection was made${NC}"
            echo -e "${BLUE}Please select an option or press Esc to cancel${NC}"
            ;;
        "invalid_selection")
            echo -e "${YELLOW}Invalid selection: $details${NC}"
            echo -e "${BLUE}Please try again with a valid option${NC}"
            ;;
        "connection_timeout")
            echo -e "${YELLOW}Connection attempt timed out${NC}"
            echo -e "${BLUE}This may be due to network issues or instance unavailability${NC}"
            ;;
        "unexpected_error")
            echo -e "${YELLOW}An unexpected error occurred${NC}"
            if [[ -n "$details" ]]; then
                echo -e "${BLUE}Details: $details${NC}"
            fi
            echo -e "${BLUE}Please try again or contact support if the issue persists${NC}"
            ;;
        *)
            echo -e "${YELLOW}Unknown error occurred${NC}"
            if [[ -n "$details" ]]; then
                echo -e "${BLUE}Details: $details${NC}"
            fi
            ;;
    esac
    
    echo
    echo -e "${BLUE}Press Enter to continue...${NC}"
    read -r
}

# Handle unexpected script termination
handle_unexpected_exit() {
    local exit_code="$1"
    
    echo
    echo -e "${RED}❌ Script terminated unexpectedly (exit code: $exit_code)${NC}"
    
    case "$exit_code" in
        130)  # Ctrl+C
            echo -e "${YELLOW}Interrupted by user (Ctrl+C)${NC}"
            ;;
        143)  # SIGTERM
            echo -e "${YELLOW}Terminated by system signal${NC}"
            ;;
        *)
            echo -e "${YELLOW}Unknown termination cause${NC}"
            ;;
    esac
    
    echo -e "${BLUE}Performing cleanup...${NC}"
    cleanup
    
    echo -e "${BLUE}Thank you for using SSM Server Connect${NC}"
    exit "$exit_code"
}

# Enhanced cleanup function with better error handling
cleanup() {
    local cleanup_errors=()
    
    # Clean up temporary directory
    if [[ -d "${TEMP_DIR}" ]]; then
        if ! rm -rf "${TEMP_DIR}" 2>/dev/null; then
            cleanup_errors+=("Failed to remove temporary directory: ${TEMP_DIR}")
        fi
    fi
    
    # Clean up any background processes
    local bg_jobs
    bg_jobs=$(jobs -p)
    if [[ -n "$bg_jobs" ]]; then
        for job_pid in $bg_jobs; do
            if kill -0 "$job_pid" 2>/dev/null; then
                kill "$job_pid" 2>/dev/null || cleanup_errors+=("Failed to terminate background process: $job_pid")
            fi
        done
    fi
    
    # Report cleanup errors if any
    if [[ ${#cleanup_errors[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Cleanup warnings:${NC}" >&2
        for error in "${cleanup_errors[@]}"; do
            echo -e "  ${YELLOW}• $error${NC}" >&2
        done
    fi
}

# Enhanced signal handling
setup_signal_handlers() {
    # Handle Ctrl+C (SIGINT)
    trap 'handle_unexpected_exit 130' INT
    
    # Handle termination (SIGTERM)
    trap 'handle_unexpected_exit 143' TERM
    
    # Handle normal exit
    trap 'cleanup' EXIT
    
    # Handle errors (if set -e is used)
    trap 'handle_unexpected_exit $?' ERR
}

# Confirm user action for critical operations
confirm_action() {
    local action="$1"
    local default_response="${2:-n}"
    local prompt_message="${3:-Are you sure you want to $action?}"
    
    echo -e "${YELLOW}$prompt_message${NC}"
    
    if [[ "$default_response" == "y" ]]; then
        echo -e "${BLUE}[Y/n]:${NC} "
    else
        echo -e "${BLUE}[y/N]:${NC} "
    fi
    
    local response
    read -r response
    
    # Use default if no response
    if [[ -z "$response" ]]; then
        response="$default_response"
    fi
    
    case "${response,,}" in
        y|yes)
            return 0
            ;;
        n|no)
            return 1
            ;;
        *)
            echo -e "${YELLOW}Please answer yes (y) or no (n)${NC}"
            confirm_action "$action" "$default_response" "$prompt_message"
            ;;
    esac
}

# Wait for user input with timeout
wait_for_user_input() {
    local timeout_seconds="${1:-30}"
    local prompt_message="${2:-Press Enter to continue or wait $timeout_seconds seconds...}"
    
    echo -e "${BLUE}$prompt_message${NC}"
    
    if read -t "$timeout_seconds" -r; then
        return 0  # User provided input
    else
        echo
        echo -e "${YELLOW}Timeout reached, continuing automatically...${NC}"
        return 1  # Timeout occurred
    fi
}

# Validate system environment before starting
validate_environment() {
    local validation_errors=()
    
    # Check if running on supported OS
    case "$(uname -s)" in
        Darwin*)
            # macOS - supported
            ;;
        Linux*)
            # Linux - supported
            ;;
        *)
            validation_errors+=("Unsupported operating system: $(uname -s)")
            ;;
    esac
    
    # Check if /tmp is writable
    if [[ ! -w "/tmp" ]]; then
        validation_errors+=("/tmp directory is not writable")
    fi
    
    # Check available disk space in /tmp (at least 10MB)
    local available_space
    if command -v df >/dev/null 2>&1; then
        available_space=$(df /tmp | awk 'NR==2 {print $4}')
        if [[ "$available_space" -lt 10240 ]]; then  # 10MB in KB
            validation_errors+=("Insufficient disk space in /tmp (less than 10MB available)")
        fi
    fi
    
    # Check if terminal supports colors
    if [[ -z "$TERM" || "$TERM" == "dumb" ]]; then
        echo -e "${YELLOW}⚠ Terminal may not support colors properly${NC}"
    fi
    
    # Report validation errors
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Environment validation failed:${NC}"
        for error in "${validation_errors[@]}"; do
            echo -e "  ${RED}• $error${NC}"
        done
        echo
        return 1
    fi
    
    return 0
}

# Set up cleanup trap and signal handlers
setup_signal_handlers

# SSM Connection Management Functions

# Test SSM connection capability for a specific instance
test_ssm_connection() {
    local instance_id="$1"
    local region="$2"
    local profile="$3"
    
    echo -e "${BLUE}Testing SSM connection to instance: ${instance_id}${NC}"
    
    # First, verify the instance is still online in SSM
    local ssm_status_cmd=(
        aws ssm describe-instance-information
        --profile "$profile"
        --region "$region"
        --filters "Key=InstanceIds,Values=$instance_id"
        --query 'InstanceInformationList[0].{PingStatus:PingStatus,LastPingDateTime:LastPingDateTime}'
        --output json
    )
    
    local ssm_status
    if ! ssm_status=$(aws_exec "${ssm_status_cmd[@]}" 2>&1); then
        echo -e "${RED}❌ Failed to check SSM status for instance${NC}"
        echo -e "${RED}Error: $ssm_status${NC}"
        return 1
    fi
    
    # Parse SSM status
    local ping_status
    if ! ping_status=$(echo "$ssm_status" | jq -r '.PingStatus // "Unknown"' 2>/dev/null); then
        ping_status="Unknown"
    fi
    
    if [[ "$ping_status" != "Online" ]]; then
        echo -e "${RED}❌ Instance is not online in SSM${NC}"
        echo -e "${YELLOW}Current status: $ping_status${NC}"
        echo -e "${BLUE}Possible causes:${NC}"
        echo -e "  • SSM Agent is not running on the instance"
        echo -e "  • Instance has network connectivity issues"
        echo -e "  • Instance IAM role lacks required permissions"
        echo -e "  • Instance is stopped or terminated"
        echo
        echo -e "${BLUE}Troubleshooting steps:${NC}"
        echo -e "  1. Verify instance is running: aws ec2 describe-instances --instance-ids $instance_id"
        echo -e "  2. Check SSM Agent status on instance: sudo systemctl status amazon-ssm-agent"
        echo -e "  3. Verify IAM role has AmazonSSMManagedInstanceCore policy"
        echo -e "  4. Check VPC endpoints for SSM if using private subnets"
        echo
        return 1
    fi
    
    # Test Session Manager connectivity specifically
    echo -e "${BLUE}Testing Session Manager connectivity...${NC}"
    
    # Check if Session Manager plugin is available
    if ! command -v session-manager-plugin >/dev/null 2>&1; then
        echo -e "${RED}❌ Session Manager plugin not found${NC}"
        echo -e "${BLUE}Install with: curl \"https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip\" -o \"sessionmanager-bundle.zip\"${NC}"
        return 1
    fi
    
    # Test Session Manager permissions by attempting to start a session with a timeout
    local session_test_cmd=(
        timeout 5
        aws ssm start-session
        --profile "$profile"
        --region "$region"
        --target "$instance_id"
        --document-name "AWS-StartSSHSession"
    )
    
    echo -e "${BLUE}Performing quick Session Manager connectivity test...${NC}"
    local session_test_result
    session_test_result=$(aws_exec "${session_test_cmd[@]}" 2>&1 || true)
    
    # Analyze the test result
    if echo "$session_test_result" | grep -q "AccessDenied"; then
        echo -e "${RED}❌ Session Manager access denied${NC}"
        echo -e "  • Your AWS user/role needs ssm:StartSession permission"
        echo -e "  • Instance IAM role needs ssm:UpdateInstanceInformation permission"
        echo -e "  • Check Session Manager preferences in AWS console"
        return 1
    elif echo "$session_test_result" | grep -q "InvalidInstanceId"; then
        echo -e "${RED}❌ Invalid instance for Session Manager${NC}"
        echo -e "  • Instance may not be registered with SSM"
        echo -e "  • Instance may be in different region"
        return 1
    elif echo "$session_test_result" | grep -q "TargetNotConnected"; then
        echo -e "${RED}❌ Instance not connected to Session Manager${NC}"
        echo -e "  • SSM Agent may not be running"
        echo -e "  • Network connectivity issues"
        return 1
    elif echo "$session_test_result" | grep -q "timeout"; then
        echo -e "${YELLOW}⚠ Session Manager test timed out${NC}"
        echo -e "${GREEN}✓ Basic connectivity appears OK (proceeding with caution)${NC}"
        return 0
    else
        echo -e "${GREEN}✓ Session Manager connectivity test passed${NC}"
        return 0
    fi
}

# Establish SSM Session Manager connection
establish_ssm_session() {
    local instance_id="$1"
    local region="$2"
    local profile="$3"
    
    # Clean the instance ID - remove any whitespace or special characters
    instance_id=$(echo "$instance_id" | tr -d '[:space:]' | grep -o 'i-[0-9a-f]\+' | head -1)
    
    echo -e "${GREEN}Establishing SSM Session Manager connection...${NC}"
    echo -e "${BLUE}Instance: $instance_id${NC}"
    echo -e "${BLUE}Region: $region${NC}"
    echo -e "${BLUE}Profile: $profile${NC}"
    echo
    
    # Prepare the SSM start-session command
    local session_cmd=(
        aws ssm start-session
        --profile "$profile"
        --region "$region"
        --target "$instance_id"
    )
    
    echo -e "${YELLOW}Starting interactive shell session...${NC}"
    echo -e "${BLUE}Note: Type 'exit' to end the session and return to instance selection${NC}"
    echo -e "${BLUE}Press Enter to continue or Ctrl+C to cancel...${NC}"
    
    # Handle user input with timeout
    if ! wait_for_user_input 30 "Press Enter to continue or wait 30 seconds..."; then
        echo -e "${BLUE}Proceeding automatically...${NC}"
    fi
    
    # Clear screen for better session experience
    clear
    
    echo "═══════════════════════════════════════════════════════════════"
    echo "  SSM Session Manager - Connected to $instance_id"
    echo "  Region: $region | Profile: $profile"
    echo "  Type 'exit' to end session"
    echo "═══════════════════════════════════════════════════════════════"
    echo
    
    # Execute the session command
    local session_exit_code=0
    if ! "${session_cmd[@]}"; then
        session_exit_code=$?
        echo
        echo -e "${RED}❌ SSM session failed to start${NC}"
        
        # Provide specific error guidance based on common issues
        case $session_exit_code in
            1)
                echo -e "${BLUE}Common causes for session failure:${NC}"
                echo -e "  • Session Manager plugin not installed or outdated"
                echo -e "  • Instance not reachable via SSM"
                echo -e "  • Network connectivity issues"
                echo -e "  • IAM permissions insufficient"
                ;;
            130)
                echo -e "${YELLOW}Session was interrupted by user (Ctrl+C)${NC}"
                ;;
            *)
                echo -e "${BLUE}Unexpected error occurred (exit code: $session_exit_code)${NC}"
                echo -e "${BLUE}Please check:${NC}"
                echo -e "  • AWS CLI and Session Manager plugin versions"
                echo -e "  • Network connectivity to AWS services"
                echo -e "  • Instance SSM Agent status"
                ;;
        esac
        
        echo
        echo -e "${BLUE}For detailed troubleshooting, visit:${NC}"
        echo -e "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-troubleshooting.html"
        echo
        return $session_exit_code
    fi
    
    # Session ended normally
    echo
    echo "═══════════════════════════════════════════════════════════════"
    echo "  SSM Session Ended"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${GREEN}✓ Session completed successfully${NC}"
    echo -e "${BLUE}Returning to instance selection...${NC}"
    echo
    
    return 0
}

# Handle connection errors with detailed guidance
handle_connection_error() {
    local instance_id="$1"
    local error_type="$2"
    local error_details="$3"
    
    echo -e "${RED}❌ Connection Error for instance: $instance_id${NC}"
    echo
    
    case "$error_type" in
        "ssm_offline")
            echo -e "${YELLOW}Issue: Instance is not online in SSM${NC}"
            echo -e "${BLUE}Resolution steps:${NC}"
            echo -e "  1. Check if instance is running:"
            echo -e "     aws ec2 describe-instances --instance-ids $instance_id --query 'Reservations[].Instances[].State.Name'"
            echo -e "  2. Verify SSM Agent is running on the instance:"
            echo -e "     sudo systemctl status amazon-ssm-agent"
            echo -e "  3. Check instance IAM role has required permissions:"
            echo -e "     - AmazonSSMManagedInstanceCore policy"
            echo -e "  4. Verify network connectivity:"
            echo -e "     - Security groups allow outbound HTTPS (443)"
            echo -e "     - VPC endpoints configured if using private subnets"
            ;;
        "permission_denied")
            echo -e "${YELLOW}Issue: Access denied for SSM operations${NC}"
            echo -e "${BLUE}Resolution steps:${NC}"
            echo -e "  1. Check your AWS user/role permissions:"
            echo -e "     - ssm:StartSession"
            echo -e "     - ssm:DescribeInstanceInformation"
            echo -e "     - ssm:SendCommand"
            echo -e "  2. Verify instance IAM role permissions:"
            echo -e "     - ssm:UpdateInstanceInformation"
            echo -e "     - ssm:SendCommandResult"
            echo -e "  3. Check for resource-based policies that might block access"
            ;;
        "session_failed")
            echo -e "${YELLOW}Issue: Session Manager connection failed${NC}"
            echo -e "${BLUE}Resolution steps:${NC}"
            echo -e "  1. Update Session Manager plugin:"
            echo -e "     brew upgrade --cask session-manager-plugin"
            echo -e "  2. Verify plugin installation:"
            echo -e "     session-manager-plugin"
            echo -e "  3. Check AWS CLI version compatibility"
            echo -e "  4. Test with AWS Console Session Manager first"
            ;;
        "network_error")
            echo -e "${YELLOW}Issue: Network connectivity problems${NC}"
            echo -e "${BLUE}Resolution steps:${NC}"
            echo -e "  1. Check internet connectivity"
            echo -e "  2. Verify AWS service endpoints are reachable"
            echo -e "  3. Check corporate firewall/proxy settings"
            echo -e "  4. Test with different network if possible"
            ;;
        *)
            echo -e "${YELLOW}Issue: Unknown error occurred${NC}"
            echo -e "${BLUE}General troubleshooting:${NC}"
            echo -e "  1. Check AWS Systems Manager console for instance status"
            echo -e "  2. Review CloudWatch logs for SSM Agent"
            echo -e "  3. Verify all prerequisites are met"
            echo -e "  4. Try connecting via AWS Console first"
            ;;
    esac
    
    if [[ -n "$error_details" ]]; then
        echo
        echo -e "${BLUE}Error details:${NC}"
        echo -e "$error_details"
    fi
    
    echo
    echo -e "${BLUE}Useful resources:${NC}"
    echo -e "  • SSM Troubleshooting: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-troubleshooting.html"
    echo -e "  • IAM Permissions: https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-create-iam-instance-profile.html"
    echo -e "  • VPC Endpoints: https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html"
    echo
    
    echo -e "${BLUE}Press Enter to return to instance selection...${NC}"
    read -r
}

# Main function with enhanced error handling and navigation
main() {
    echo "SSM Server Connect v${SCRIPT_VERSION}"
    echo "Initializing..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
                    echo -e "${RED}❌ --region requires a value${NC}"
                    echo "Use --help for usage information"
                    exit 1
                fi
                AWS_REGION="$2"
                # Basic validation for AWS region format
                if [[ ! "$AWS_REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
                    echo -e "${YELLOW}⚠ Warning: '$AWS_REGION' doesn't match typical AWS region format${NC}"
                    echo -e "${BLUE}Continuing anyway... (format: us-east-1, eu-west-1, etc.)${NC}"
                fi
                shift 2
                ;;
            --version)
                echo "SSM Server Connect v${SCRIPT_VERSION}"
                exit "${EXIT_SUCCESS}"
                ;;
            --version-info)
                show_version_info
                exit "${EXIT_SUCCESS}"
                ;;
            --check-updates)
                echo "SSM Server Connect v${SCRIPT_VERSION}"
                echo "Checking for updates..."
                echo
                check_for_updates "manual"
                exit "${EXIT_SUCCESS}"
                ;;
            --self-test)
                # Handle self-test in main execution section
                shift
                ;;
            --help|-h)
                echo "Usage: $SCRIPT_NAME [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --region REGION      AWS region to use (default: ${DEFAULT_REGION})"
                echo "  --version            Show version number"
                echo "  --version-info       Show detailed version and system information"
                echo "  --check-updates      Check for available updates"
                echo "  --self-test          Run system compatibility tests"
                echo "  --help, -h           Show this help message"
                echo ""
                echo "Examples:"
                echo "  $SCRIPT_NAME                      # Use default region (${DEFAULT_REGION})"
                echo "  $SCRIPT_NAME --region us-east-1   # Use specific region"
                echo "  $SCRIPT_NAME --version-info       # Show detailed version info"
                echo "  $SCRIPT_NAME --check-updates      # Check for updates"
                echo "  $SCRIPT_NAME --self-test          # Test system compatibility"
                exit "${EXIT_SUCCESS}"
                ;;
            *)
                echo -e "${RED}❌ Unknown option: $1${NC}"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Create temporary directory with error handling
    if ! mkdir -p "${TEMP_DIR}"; then
        echo -e "${RED}❌ Failed to create temporary directory: ${TEMP_DIR}${NC}"
        echo -e "${YELLOW}Please check disk space and permissions for /tmp${NC}"
        exit 1
    fi
    
    # Validate temporary directory is writable
    if ! touch "${TEMP_DIR}/test_write" 2>/dev/null; then
        echo -e "${RED}❌ Temporary directory is not writable: ${TEMP_DIR}${NC}"
        echo -e "${YELLOW}Please check permissions for /tmp${NC}"
        exit 1
    fi
    rm -f "${TEMP_DIR}/test_write" 2>/dev/null
    
    # Validate environment before starting
    if ! validate_environment; then
        echo -e "${YELLOW}Please resolve the above issues and try again${NC}"
        exit 1
    fi
    
    # Check for updates (non-blocking, auto mode)
    check_for_updates "auto" &
    local update_check_pid=$!
    
    # Give update check a moment to complete, but don't wait
    sleep 0.5
    if kill -0 "$update_check_pid" 2>/dev/null; then
        # Still running, kill it to avoid blocking
        kill "$update_check_pid" 2>/dev/null
    fi
    
    # Main workflow loop to handle navigation back to profile selection
    while true; do
        local workflow_restart=false
        
        # 1. Check requirements
        if ! check_requirements; then
            display_user_error "unexpected_error" "requirements" "Failed to verify system requirements"
            exit "${EXIT_MISSING_DEPS}"
        fi
        
        # 2. Select AWS profile
        if ! select_profile; then
            local profile_result=$?
            case $profile_result in
                "${EXIT_USER_CANCELLED}")
                    handle_user_cancellation "profile_selection" "Profile selection cancelled"
                    ;;
                *)
                    display_user_error "unexpected_error" "profile_selection" "Failed to select AWS profile"
                    exit "${EXIT_AUTH_FAILED}"
                    ;;
            esac
        fi
        
        # 3. Authenticate
        if ! check_aws_auth "$AWS_PROFILE"; then
            display_user_error "unexpected_error" "authentication" "AWS authentication failed for profile: $AWS_PROFILE"
            
            # Ask user if they want to try a different profile
            if confirm_action "try a different AWS profile" "y" "Would you like to select a different AWS profile?"; then
                continue  # Restart the workflow
            else
                exit "${EXIT_AUTH_FAILED}"
            fi
        fi
        
        # 4. List SSM instances
        if ! list_ssm_instances "$AWS_REGION" "$AWS_PROFILE"; then
            echo -e "${YELLOW}No instances available for connection in region: ${AWS_REGION}${NC}"
            
            # Ask user if they want to try a different region or profile
            echo -e "${BLUE}Options:${NC}"
            echo -e "  1. Try a different AWS profile"
            echo -e "  2. Exit"
            echo -e "${BLUE}Choose an option [1-2]:${NC} "
            
            local choice
            read -r choice
            
            case "$choice" in
                1)
                    continue  # Restart workflow with profile selection
                    ;;
                2|"")
                    exit "${EXIT_NO_INSTANCES}"
                    ;;
                *)
                    echo -e "${YELLOW}Invalid choice, exiting...${NC}"
                    exit "${EXIT_NO_INSTANCES}"
                    ;;
            esac
        fi
        
        # 5. Enrich instance data with EC2 information (with caching)
        local cache_file="${TEMP_DIR}/ec2_cache_${AWS_PROFILE}_${AWS_REGION}.json"
        local cache_age=300  # 5 minutes cache
        
        # Check if we have recent cached data
        if [[ -f "$cache_file" ]]; then
            local cache_timestamp
            cache_timestamp=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
            local current_timestamp
            current_timestamp=$(date +%s)
            
            if [[ $((current_timestamp - cache_timestamp)) -lt $cache_age ]]; then
                echo -e "${GREEN}✓ Using cached EC2 data ($(((current_timestamp - cache_timestamp)))s old)${NC}"
                cp "$cache_file" "${TEMP_DIR}/ec2_details.json"
            else
                echo -e "${BLUE}Cache expired, fetching fresh data...${NC}"
                if enrich_instance_data "$AWS_REGION" "$AWS_PROFILE"; then
                    cp "${TEMP_DIR}/ec2_details.json" "$cache_file"
                fi
            fi
        else
            echo -e "${BLUE}No cache found, fetching EC2 data...${NC}"
            if enrich_instance_data "$AWS_REGION" "$AWS_PROFILE"; then
                cp "${TEMP_DIR}/ec2_details.json" "$cache_file"
            else
                echo -e "${YELLOW}⚠ Failed to enrich instance data, continuing with basic information${NC}"
                wait_for_user_input 3 "Continuing in 3 seconds..."
            fi
        fi
        
        echo -e "${GREEN}✓ Instance data preparation complete${NC}"
        echo -e "Profile: ${AWS_PROFILE}"
        echo -e "Region: ${AWS_REGION}"
        echo
        
        # 6. Instance selection and connection loop
        while true; do
            local selected_instance_id
            local selection_result
            
            # Show FZF interface for instance selection
            if selected_instance_id=$(select_instance "$AWS_REGION" "$AWS_PROFILE"); then
                selection_result=$?
                
                if [[ $selection_result -eq 0 && -n "$selected_instance_id" ]]; then
                    echo -e "${BLUE}Connecting to instance: ${selected_instance_id}${NC}"
                    
                    # Test SSM connection capability first
                    if test_ssm_connection "$selected_instance_id" "$AWS_REGION" "$AWS_PROFILE"; then
                        # Establish the SSM session
                        local session_result=0
                        if ! establish_ssm_session "$selected_instance_id" "$AWS_REGION" "$AWS_PROFILE"; then
                            session_result=$?
                            handle_connection_error "$selected_instance_id" "session_failed" "Session Manager connection failed"
                        fi
                        
                        # Handle session result
                        case $session_result in
                            0)
                                echo -e "${GREEN}✓ Session completed successfully${NC}"
                                ;;
                            130)
                                echo -e "${YELLOW}Session interrupted by user${NC}"
                                ;;
                            *)
                                echo -e "${YELLOW}Session ended with exit code: $session_result${NC}"
                                ;;
                        esac
                    else
                        handle_connection_error "$selected_instance_id" "ssm_offline" "Instance is not available for SSM connection"
                    fi
                    
                    # Ask user what to do next
                    echo
                    echo -e "${BLUE}What would you like to do next?${NC}"
                    echo -e "  1. Select another instance"
                    echo -e "  2. Change AWS profile"
                    echo -e "  3. Exit"
                    echo -e "${BLUE}Choose an option [1-3]:${NC} "
                    
                    local next_action
                    read -r next_action
                    
                    case "$next_action" in
                        1|"")
                            continue  # Continue instance selection loop
                            ;;
                        2)
                            workflow_restart=true
                            break  # Break instance loop to restart workflow
                            ;;
                        3)
                            echo -e "${BLUE}Thank you for using SSM Server Connect!${NC}"
                            exit "${EXIT_SUCCESS}"
                            ;;
                        *)
                            echo -e "${YELLOW}Invalid choice, returning to instance selection...${NC}"
                            continue
                            ;;
                    esac
                fi
            else
                selection_result=$?
            fi
            
            # Handle different selection results
            case $selection_result in
                2)  # User cancelled instance selection
                    if handle_user_cancellation "instance_selection" "Instance selection cancelled"; then
                        workflow_restart=true
                        break  # Break to restart workflow
                    else
                        exit "${EXIT_USER_CANCELLED}"
                    fi
                    ;;
                3)  # Go back to profile selection
                    if handle_navigation_back "instance_selection"; then
                        workflow_restart=true
                        break  # Break to restart workflow
                    else
                        exit "${EXIT_USER_CANCELLED}"
                    fi
                    ;;
                *)  # Error or other cases
                    display_user_error "unexpected_error" "instance_selection" "Instance selection failed with code: $selection_result"
                    
                    # Ask user if they want to try again
                    if confirm_action "try again" "y" "Would you like to try selecting an instance again?"; then
                        continue  # Continue instance selection loop
                    else
                        exit "${EXIT_CONNECTION_FAILED}"
                    fi
                    ;;
            esac
        done
        
        # Check if we need to restart the workflow
        if [[ "$workflow_restart" == true ]]; then
            echo -e "${BLUE}Restarting workflow...${NC}"
            continue  # Restart main workflow loop
        else
            break  # Exit main workflow loop
        fi
    done
}

# Check for updates from GitHub releases
check_for_updates() {
    local check_type="${1:-manual}"  # manual or auto
    
    if [[ "$check_type" == "auto" ]]; then
        echo -e "${BLUE}Checking for updates...${NC}"
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        if [[ "$check_type" == "manual" ]]; then
            echo -e "${YELLOW}⚠ curl not available, cannot check for updates${NC}"
        fi
        return 1
    fi
    
    # Get latest release information from GitHub API
    local latest_release_info
    if ! latest_release_info=$(curl -s --connect-timeout 5 --max-time 10 "$UPDATE_CHECK_URL" 2>/dev/null); then
        if [[ "$check_type" == "manual" ]]; then
            echo -e "${YELLOW}⚠ Failed to check for updates (network error)${NC}"
        fi
        return 1
    fi
    
    # Parse latest version from GitHub API response
    local latest_version
    if ! latest_version=$(echo "$latest_release_info" | jq -r '.tag_name // empty' 2>/dev/null); then
        if [[ "$check_type" == "manual" ]]; then
            echo -e "${YELLOW}⚠ Failed to parse update information${NC}"
        fi
        return 1
    fi
    
    # Remove 'v' prefix if present
    latest_version="${latest_version#v}"
    
    if [[ -z "$latest_version" ]]; then
        if [[ "$check_type" == "manual" ]]; then
            echo -e "${YELLOW}⚠ No release information found${NC}"
        fi
        return 1
    fi
    
    # Compare versions (simple string comparison for semantic versioning)
    if [[ "$latest_version" != "$SCRIPT_VERSION" ]]; then
        # Check if latest version is newer (basic semantic version comparison)
        if version_compare "$SCRIPT_VERSION" "$latest_version"; then
            echo -e "${GREEN}🎉 New version available: v${latest_version} (current: v${SCRIPT_VERSION})${NC}"
            echo
            
            # Get release notes
            local release_notes
            release_notes=$(echo "$latest_release_info" | jq -r '.body // "No release notes available"' 2>/dev/null)
            
            if [[ -n "$release_notes" && "$release_notes" != "No release notes available" ]]; then
                echo -e "${BLUE}Release Notes:${NC}"
                echo "$release_notes" | head -10  # Show first 10 lines
                echo
            fi
            
            # Show update instructions
            echo -e "${BLUE}To update:${NC}"
            echo -e "  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh | bash"
            echo
            echo -e "${BLUE}Or visit: https://github.com/${GITHUB_REPO}/releases/latest${NC}"
            echo
            
            return 0  # Update available
        else
            if [[ "$check_type" == "manual" ]]; then
                echo -e "${GREEN}✓ You have the latest version (v${SCRIPT_VERSION})${NC}"
            fi
            return 2  # No update needed
        fi
    else
        if [[ "$check_type" == "manual" ]]; then
            echo -e "${GREEN}✓ You have the latest version (v${SCRIPT_VERSION})${NC}"
        fi
        return 2  # No update needed
    fi
}

# Simple semantic version comparison (returns 0 if first version is older)
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Split versions into arrays
    IFS='.' read -ra ver1_parts <<< "$version1"
    IFS='.' read -ra ver2_parts <<< "$version2"
    
    # Pad arrays to same length
    local max_length=${#ver1_parts[@]}
    if [[ ${#ver2_parts[@]} -gt $max_length ]]; then
        max_length=${#ver2_parts[@]}
    fi
    
    # Compare each part
    for ((i=0; i<max_length; i++)); do
        local part1=${ver1_parts[i]:-0}
        local part2=${ver2_parts[i]:-0}
        
        # Remove non-numeric characters for comparison
        part1=$(echo "$part1" | sed 's/[^0-9]//g')
        part2=$(echo "$part2" | sed 's/[^0-9]//g')
        
        # Default to 0 if empty
        part1=${part1:-0}
        part2=${part2:-0}
        
        if [[ $part1 -lt $part2 ]]; then
            return 0  # version1 is older
        elif [[ $part1 -gt $part2 ]]; then
            return 1  # version1 is newer
        fi
        # If equal, continue to next part
    done
    
    return 1  # Versions are equal
}

# Show detailed version information
show_version_info() {
    echo "SSM Server Connect"
    echo "=================="
    echo "Version: v${SCRIPT_VERSION}"
    echo "GitHub: https://github.com/${GITHUB_REPO}"
    echo
    
    # Show system information
    echo "System Information:"
    echo "  OS: $(uname -s) $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo "  Shell: ${SHELL##*/}"
    echo
    
    # Show dependency versions
    echo "Dependencies:"
    
    if command -v aws &> /dev/null; then
        local aws_version
        aws_version=$(aws --version 2>&1 | head -n1 | cut -d' ' -f1-2)
        echo "  AWS CLI: $aws_version"
    else
        echo "  AWS CLI: Not installed"
    fi
    
    if command -v session-manager-plugin &> /dev/null; then
        local ssm_version
        ssm_version=$(session-manager-plugin --version 2>/dev/null || echo "Unknown")
        echo "  Session Manager Plugin: $ssm_version"
    else
        echo "  Session Manager Plugin: Not installed"
    fi
    
    if command -v fzf &> /dev/null; then
        local fzf_version
        fzf_version=$(fzf --version | cut -d' ' -f1)
        echo "  FZF: $fzf_version"
    else
        echo "  FZF: Not installed"
    fi
    
    if command -v jq &> /dev/null; then
        local jq_version
        jq_version=$(jq --version)
        echo "  jq: $jq_version"
    else
        echo "  jq: Not installed"
    fi
    
    echo
    
    # Check for updates
    echo "Checking for updates..."
    check_for_updates "manual"
}

# Self-test function for integration testing
self_test() {
    echo "SSM Server Connect - Self Test"
    echo "=============================="
    echo
    
    local test_errors=()
    
    # Test 1: Environment validation
    echo -n "Testing environment validation... "
    if validate_environment >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        test_errors+=("Environment validation failed")
    fi
    
    # Test 2: Requirements check
    echo -n "Testing requirements check... "
    if check_requirements >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        test_errors+=("Requirements check failed")
    fi
    
    # Test 3: Temporary directory creation
    echo -n "Testing temporary directory creation... "
    local test_temp_dir="/tmp/ssm_test_$$"
    if mkdir -p "$test_temp_dir" && touch "$test_temp_dir/test" && rm -rf "$test_temp_dir"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        test_errors+=("Temporary directory creation failed")
    fi
    
    # Test 4: AWS CLI basic functionality
    echo -n "Testing AWS CLI availability... "
    if aws --version >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        test_errors+=("AWS CLI not available")
    fi
    
    # Test 5: FZF functionality
    echo -n "Testing FZF functionality... "
    if echo "test" | fzf --filter="test" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        test_errors+=("FZF not working properly")
    fi
    
    # Test 6: JSON processing
    echo -n "Testing JSON processing... "
    if echo '{"test": "value"}' | jq -r '.test' >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        test_errors+=("JSON processing (jq) failed")
    fi
    
    echo
    
    # Report results
    if [[ ${#test_errors[@]} -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed! SSM Server Connect is ready to use.${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed:${NC}"
        for error in "${test_errors[@]}"; do
            echo -e "  ${RED}• $error${NC}"
        done
        echo
        echo -e "${YELLOW}Please resolve the above issues before using SSM Server Connect${NC}"
        return 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check for self-test flag in arguments
    for arg in "$@"; do
        if [[ "$arg" == "--self-test" ]]; then
            self_test
            exit $?
        fi
    done
    
    main "$@"
fi