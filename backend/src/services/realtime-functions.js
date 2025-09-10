const admin = require('firebase-admin');

// Get tool definitions for OpenAI session configuration
function getToolDefinitions() {
  return [
    {
      type: 'function',
      function: {
        name: 'create_task',
        description: 'Create a new task or reminder for the user',
        parameters: {
          type: 'object',
          properties: {
            title: {
              type: 'string',
              description: 'The title or description of the task'
            },
            dueDate: {
              type: 'string',
              description: 'Optional due date/time for the task in ISO format'
            },
            priority: {
              type: 'string',
              enum: ['low', 'medium', 'high'],
              description: 'Priority level of the task'
            }
          },
          required: ['title']
        }
      }
    },
    {
      type: 'function',
      function: {
        name: 'list_tasks',
        description: 'List all tasks or reminders',
        parameters: {
          type: 'object',
          properties: {
            filter: {
              type: 'string',
              enum: ['all', 'pending', 'completed', 'today'],
              description: 'Filter tasks by status or timeframe'
            }
          }
        }
      }
    },
    {
      type: 'function',
      function: {
        name: 'complete_task',
        description: 'Mark a task as completed',
        parameters: {
          type: 'object',
          properties: {
            taskId: {
              type: 'string',
              description: 'The ID of the task to complete'
            },
            taskTitle: {
              type: 'string',
              description: 'Alternative: the title of the task to complete if ID is not available'
            }
          }
        }
      }
    },
    {
      type: 'function',
      function: {
        name: 'delete_task',
        description: 'Delete a task or reminder',
        parameters: {
          type: 'object',
          properties: {
            taskId: {
              type: 'string',
              description: 'The ID of the task to delete'
            },
            taskTitle: {
              type: 'string',
              description: 'Alternative: the title of the task to delete if ID is not available'
            }
          }
        }
      }
    }
  ];
}

class RealtimeFunctionHandler {
  constructor(userId) {
    this.userId = userId;
    this.db = admin.firestore();
  }

  async handleFunctionCall(name, argumentsString) {
    console.log(`🔧 Handling function call: ${name}`);
    console.log(`📝 Arguments: ${argumentsString}`);

    try {
      // Parse arguments - handle empty or malformed JSON
      let args = {};
      if (argumentsString && argumentsString !== '{}') {
        try {
          args = JSON.parse(argumentsString);
        } catch (e) {
          // Try to fix truncated JSON
          const fixed = this.fixTruncatedJSON(argumentsString);
          args = JSON.parse(fixed);
        }
      }

      // Execute the appropriate function
      switch (name) {
        case 'create_task':
          return await this.createTask(args);
        case 'list_tasks':
          return await this.listTasks(args);
        case 'complete_task':
          return await this.completeTask(args);
        case 'delete_task':
          return await this.deleteTask(args);
        default:
          throw new Error(`Unknown function: ${name}`);
      }
    } catch (error) {
      console.error(`❌ Function execution error: ${error.message}`);
      return JSON.stringify({
        success: false,
        error: error.message
      });
    }
  }

  fixTruncatedJSON(json) {
    let fixed = json;
    
    // Count braces
    const openBraces = (json.match(/{/g) || []).length;
    const closeBraces = (json.match(/}/g) || []).length;
    const hasUnclosedQuote = (json.match(/"/g) || []).length % 2 !== 0;
    
    // Add closing quote if needed
    if (hasUnclosedQuote) {
      fixed += '"';
    }
    
    // Add closing braces
    fixed += '}'.repeat(openBraces - closeBraces);
    
    return fixed;
  }

  async createTask(args) {
    const title = args.title || args['task description'] || args.description;
    
    if (!title) {
      return JSON.stringify({
        success: false,
        error: 'Task title is required'
      });
    }

    try {
      const taskId = this.generateId();
      const task = {
        id: taskId,
        userId: this.userId,
        title: title,
        content: title, // UserTask model uses content field
        status: 'pending',
        priority: args.priority || 'medium',
        completed: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      };

      if (args.dueDate) {
        task.dueDate = new Date(args.dueDate);
      }

      await this.db.collection('tasks').doc(taskId).set(task);

      console.log(`✅ Task created: ${title}`);
      
      return JSON.stringify({
        success: true,
        data: {
          message: 'Task created successfully',
          taskId: taskId,
          title: title
        }
      });
    } catch (error) {
      console.error(`❌ Error creating task: ${error.message}`);
      return JSON.stringify({
        success: false,
        error: `Failed to create task: ${error.message}`
      });
    }
  }

  async listTasks(args) {
    const filter = args.filter || 'all';

    try {
      let query = this.db.collection('tasks').where('userId', '==', this.userId);

      // Apply filters
      switch (filter) {
        case 'pending':
          query = query.where('completed', '==', false);
          break;
        case 'completed':
          query = query.where('completed', '==', true);
          break;
        case 'today':
          const startOfDay = new Date();
          startOfDay.setHours(0, 0, 0, 0);
          const endOfDay = new Date();
          endOfDay.setHours(23, 59, 59, 999);
          query = query
            .where('dueDate', '>=', startOfDay)
            .where('dueDate', '<=', endOfDay);
          break;
      }

      const snapshot = await query.get();
      const tasks = [];
      
      snapshot.forEach(doc => {
        const data = doc.data();
        tasks.push({
          id: doc.id,
          title: data.title || data.content,
          completed: data.completed || false,
          priority: data.priority || 'medium',
          status: data.status || (data.completed ? 'completed' : 'pending')
        });
      });

      console.log(`✅ Found ${tasks.length} tasks`);

      return JSON.stringify({
        success: true,
        data: {
          tasks: tasks,
          count: tasks.length
        }
      });
    } catch (error) {
      console.error(`❌ Error listing tasks: ${error.message}`);
      return JSON.stringify({
        success: false,
        error: `Failed to list tasks: ${error.message}`
      });
    }
  }

  async completeTask(args) {
    let taskId = args.taskId;
    const taskTitle = args.taskTitle;

    try {
      // If no ID provided, try to find by title
      if (!taskId && taskTitle) {
        const snapshot = await this.db.collection('tasks')
          .where('userId', '==', this.userId)
          .where('title', '==', taskTitle)
          .where('completed', '==', false)
          .limit(1)
          .get();
        
        if (!snapshot.empty) {
          taskId = snapshot.docs[0].id;
        }
      }

      if (!taskId) {
        return JSON.stringify({
          success: false,
          error: 'Task not found'
        });
      }

      await this.db.collection('tasks').doc(taskId).update({
        completed: true,
        status: 'completed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      console.log(`✅ Task completed: ${taskId}`);

      return JSON.stringify({
        success: true,
        data: {
          message: 'Task marked as completed',
          taskId: taskId
        }
      });
    } catch (error) {
      console.error(`❌ Error completing task: ${error.message}`);
      return JSON.stringify({
        success: false,
        error: `Failed to complete task: ${error.message}`
      });
    }
  }

  async deleteTask(args) {
    let taskId = args.taskId;
    const taskTitle = args.taskTitle;

    try {
      // If no ID provided, try to find by title
      if (!taskId && taskTitle) {
        const snapshot = await this.db.collection('tasks')
          .where('userId', '==', this.userId)
          .where('title', '==', taskTitle)
          .limit(1)
          .get();
        
        if (!snapshot.empty) {
          taskId = snapshot.docs[0].id;
        }
      }

      if (!taskId) {
        return JSON.stringify({
          success: false,
          error: 'Task not found'
        });
      }

      await this.db.collection('tasks').doc(taskId).delete();

      console.log(`✅ Task deleted: ${taskId}`);

      return JSON.stringify({
        success: true,
        data: {
          message: 'Task deleted successfully',
          taskId: taskId
        }
      });
    } catch (error) {
      console.error(`❌ Error deleting task: ${error.message}`);
      return JSON.stringify({
        success: false,
        error: `Failed to delete task: ${error.message}`
      });
    }
  }

  generateId() {
    return 'task_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }
}

module.exports = {
  getToolDefinitions,
  RealtimeFunctionHandler
};